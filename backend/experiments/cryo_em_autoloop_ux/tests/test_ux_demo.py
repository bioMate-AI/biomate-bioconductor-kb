"""
Tests for the CryoEM auto-loop UX layer.

Validates:
  1. Knowledge base completeness — all gates have KnowledgeEntry objects with
     required fields (source_file, source_text, paper_ref, paper_doi, finding)
  2. EnrichedRemediation — knowledge entries are attached for known gates
  3. ProgressReporter — all required SSE event types are emitted
  4. Demo scenarios — correct outcomes + correct SSE event structure
  5. SSE event schema — matches frontend contract from architecture doc

Run with:
    python -m pytest tests/test_ux_demo.py -v
(from backend/experiments/cryo_em_autoloop_ux/)
"""

from __future__ import annotations

import json
import sys
import tempfile
from io import StringIO
from pathlib import Path

import pytest
from rich.console import Console

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent.parent))

from cryo_em_autoloop.params import CryoEMParams
from cryo_em_autoloop.qc_evaluator import CryoEMQCEvaluator
from cryo_em_autoloop_ux.knowledge_base import GATE_KNOWLEDGE, get_knowledge, KnowledgeEntry
from cryo_em_autoloop_ux.enriched_tuner import KnowledgeEnrichedTuner
from cryo_em_autoloop_ux.progress_reporter import ProgressReporter
from cryo_em_autoloop_ux.demo import SCENARIOS, run_scenario


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture
def tmpdir():
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


@pytest.fixture
def silent_console() -> Console:
    """Console that writes to /dev/null for tests."""
    return Console(file=StringIO(), highlight=False, markup=False)


@pytest.fixture
def silent_reporter(silent_console) -> tuple[ProgressReporter, StringIO]:
    buf = StringIO()
    reporter = ProgressReporter(console=silent_console, json_sink=buf, verbose=True)
    return reporter, buf


# ── 1. Knowledge base completeness ───────────────────────────────────────────

class TestKnowledgeBase:

    REQUIRED_GATES = [
        "motion_drift", "per_frame_drift", "ctf_fit_quality", "astigmatism",
        "junk_fraction", "particle_yield", "orientation_anisotropy",
        "abinitio_class_score", "abinitio_resolution", "fsc_resolution",
    ]

    def test_all_gates_have_knowledge_entries(self):
        for gate in self.REQUIRED_GATES:
            entries = get_knowledge(gate)
            assert len(entries) >= 1, f"Gate '{gate}' has no knowledge entries"

    def test_entries_have_required_fields(self):
        """Every KnowledgeEntry must have all five fields non-empty."""
        for gate, entries in GATE_KNOWLEDGE.items():
            for e in entries:
                assert isinstance(e, KnowledgeEntry), (
                    f"{gate}: expected KnowledgeEntry, got {type(e)}"
                )
                assert e.source_file, f"{gate}: missing source_file"
                assert e.source_text, f"{gate}: missing source_text"
                assert e.paper_ref,   f"{gate}: missing paper_ref"
                assert e.paper_doi,   f"{gate}: missing paper_doi"
                assert e.finding,     f"{gate}: missing finding"

    def test_doi_format_no_prefix(self):
        """paper_doi should NOT include the https://doi.org/ prefix."""
        for gate, entries in GATE_KNOWLEDGE.items():
            for e in entries:
                assert not e.paper_doi.startswith("http"), (
                    f"{gate}: paper_doi should not start with http; got {e.paper_doi!r}"
                )

    def test_source_file_points_to_skill_docs(self):
        """All source_file values must be under docs/cryo_em_skills/."""
        for gate, entries in GATE_KNOWLEDGE.items():
            for e in entries:
                assert "cryo_em_skills" in e.source_file or "docs/" in e.source_file, (
                    f"{gate}: source_file should be inside docs/cryo_em_skills/; "
                    f"got {e.source_file!r}"
                )

    def test_to_dict_has_all_fields(self):
        for gate, entries in GATE_KNOWLEDGE.items():
            for e in entries:
                d = e.to_dict()
                for key in ("source_file", "source_text", "paper_ref", "paper_doi", "finding"):
                    assert key in d, (
                        f"Missing key '{key}' in KnowledgeEntry.to_dict() for gate {gate}"
                    )

    def test_key_sources_are_present(self):
        """Spot-check that the primary BioMate skill document sources are present."""
        # VMAT2 Nature 2023 must be the primary source for motion drift threshold
        motion_dois = [e.paper_doi for e in get_knowledge("motion_drift")]
        assert "10.1038/s41586-023-06328-6" in motion_dois, (
            "VMAT2 Nature 2023 (10.1038/s41586-023-06328-6) must be cited for motion_drift"
        )

        # CaV1.2 Cell 2023 must be present in CTF quality (two labs = same threshold)
        ctf_dois = [e.paper_doi for e in get_knowledge("ctf_fit_quality")]
        assert "10.1016/j.cell.2023.08.002" in ctf_dois, (
            "CaV1.2 Cell 2023 (10.1016/j.cell.2023.08.002) must be in ctf_fit_quality"
        )

        # VMAT2 must also be cited for CTF (CTFFIND4 settings from Methods)
        assert "10.1038/s41586-023-06328-6" in ctf_dois, (
            "VMAT2 Nature 2023 must be in ctf_fit_quality (CTFFIND4 settings)"
        )

        # FSC resolution must cite the primary study using 0.143 criterion
        fsc_dois = [e.paper_doi for e in get_knowledge("fsc_resolution")]
        assert len(fsc_dois) >= 1, "fsc_resolution must have at least one knowledge entry"
        # General framework source must be present
        fsc_sources = [e.source_file for e in get_knowledge("fsc_resolution")]
        assert any("GENERAL_FRAMEWORK" in s or "INDEX" in s for s in fsc_sources), (
            "fsc_resolution should cite the general framework / cross-study index"
        )

        # Ab initio entries must cite the VMAT2 paper (used 4 ab initio classes)
        abinit_dois = [e.paper_doi for e in get_knowledge("abinitio_class_score")]
        assert "10.1038/s41586-023-06328-6" in abinit_dois, (
            "VMAT2 Nature 2023 must be cited for abinitio_class_score (used 4 classes)"
        )


# ── 2. EnrichedRemediation ────────────────────────────────────────────────────

class TestEnrichedRemediation:

    def _make_qc_fail(self, gate: str) -> tuple[CryoEMParams, "PhaseQCResult"]:
        ev = CryoEMQCEvaluator()
        if gate == "motion_drift":
            metrics = {"mean_total_drift_A": 80.0, "mean_per_frame_drift_A": 1.0,
                       "mean_ctf_fit_quality": 0.88, "mean_astigmatism_A": 300.0}
            qc = ev.evaluate_phase_A(metrics)
        elif gate == "junk_fraction":
            metrics = {"junk_fraction": 0.80, "num_particles_selected": 50_000, "min_particles_required": 5_000}
            qc = ev.evaluate_phase_B(metrics)
        elif gate == "orientation_anisotropy":
            metrics = {"orientation_anisotropy": 15.0, "mean_class_quality": 0.5}
            qc = ev.evaluate_phase_C(metrics)
        elif gate == "abinitio_class_score":
            metrics = {"best_abinitio_class_score": 0.05, "best_abinitio_resolution_A": 30.0}
            qc = ev.evaluate_phase_D(metrics)
        else:
            raise ValueError(f"No test setup for gate {gate!r}")
        return CryoEMParams(), qc

    def test_enriched_remediations_have_citations(self):
        tuner = KnowledgeEnrichedTuner()
        for gate in ["motion_drift", "junk_fraction", "orientation_anisotropy", "abinitio_class_score"]:
            params, qc = self._make_qc_fail(gate)
            new_params, remeds = tuner.remediate(qc, params)
            gate_remeds = [r for r in remeds if r.gate == gate]
            assert len(gate_remeds) >= 1, f"No remediation for gate {gate}"
            rem = gate_remeds[0]
            assert rem.has_citations(), f"Remediation for gate {gate} has no citations"
            assert len(rem.citations) >= 1

    def test_to_dict_is_json_serialisable(self):
        tuner = KnowledgeEnrichedTuner()
        params, qc = self._make_qc_fail("motion_drift")
        _, remeds = tuner.remediate(qc, params)
        for r in remeds:
            d = r.to_dict()
            json.dumps(d)  # must not raise

    def test_param_changes_present(self):
        tuner = KnowledgeEnrichedTuner()
        params = CryoEMParams(micrograph_batch_size=200)
        ev = CryoEMQCEvaluator()
        qc = ev.evaluate_phase_A({
            "mean_total_drift_A": 80.0, "mean_per_frame_drift_A": 1.0,
            "mean_ctf_fit_quality": 0.88, "mean_astigmatism_A": 300.0,
        })
        new_params, remeds = tuner.remediate(qc, params)
        motion_rems = [r for r in remeds if r.gate == "motion_drift"]
        assert len(motion_rems) == 1
        assert "micrograph_batch_size" in motion_rems[0].param_changes
        assert motion_rems[0].param_changes["micrograph_batch_size"] == 100  # halved


# ── 3. ProgressReporter event emission ───────────────────────────────────────

class TestProgressReporter:

    def _run_minimal_reporter(self) -> tuple[ProgressReporter, list[dict]]:
        console = Console(file=StringIO())
        buf = StringIO()
        reporter = ProgressReporter(console=console, json_sink=buf, verbose=False)

        ev = CryoEMQCEvaluator()
        qc_pass = ev.evaluate_phase_A({
            "mean_total_drift_A": 20.0, "mean_per_frame_drift_A": 1.0,
            "mean_ctf_fit_quality": 0.88, "mean_astigmatism_A": 300.0,
        })

        reporter.phase_start("phase_A", 1, {"micrograph_batch_size": 200})
        reporter.phase_running("phase_A", "Processing 300 micrographs...")
        reporter.gate_results(qc_pass)
        reporter.phase_passed("phase_A", 1, "GOLD")

        events = [json.loads(l) for l in buf.getvalue().strip().splitlines() if l.strip()]
        return reporter, events

    def test_events_emitted(self):
        _, events = self._run_minimal_reporter()
        types = [e["type"] for e in events]
        assert "autoloop_phase_start" in types
        assert "autoloop_running" in types
        assert "autoloop_gate_results" in types
        assert "autoloop_phase_complete" in types

    def test_all_events_have_ts(self):
        _, events = self._run_minimal_reporter()
        for e in events:
            assert "ts" in e, f"Event {e['type']} missing 'ts'"

    def test_gate_results_event_schema(self):
        _, events = self._run_minimal_reporter()
        gate_events = [e for e in events if e["type"] == "autoloop_gate_results"]
        assert len(gate_events) == 1
        ge = gate_events[0]
        assert "passed" in ge
        assert "gates" in ge
        assert isinstance(ge["gates"], list)
        for g in ge["gates"]:
            for key in ("gate", "action", "level", "value", "threshold"):
                assert key in g, f"Gate result missing key {key!r}"

    def test_retry_event_contains_citations(self):
        console = Console(file=StringIO())
        buf = StringIO()
        reporter = ProgressReporter(console=console, json_sink=buf, verbose=True)

        ev = CryoEMQCEvaluator()
        qc_fail = ev.evaluate_phase_A({
            "mean_total_drift_A": 80.0, "mean_per_frame_drift_A": 1.0,
            "mean_ctf_fit_quality": 0.88, "mean_astigmatism_A": 300.0,
        })
        tuner = KnowledgeEnrichedTuner()
        _, enriched_remeds = tuner.remediate(qc_fail, CryoEMParams())

        reporter.retry_triggered("phase_A", 1, enriched_remeds, 2)

        events = [json.loads(l) for l in buf.getvalue().strip().splitlines() if l.strip()]
        update_events = [e for e in events if e["type"] == "autoloop_update"]
        assert len(update_events) == 1
        ue = update_events[0]
        assert "remediations" in ue
        for r in ue["remediations"]:
            assert "citations" in r, "Remediation in SSE event must have citations"
            assert len(r["citations"]) >= 1, "At least one citation required"
            c = r["citations"][0]
            for key in ("source_file", "source_text", "paper_ref", "paper_doi", "finding"):
                assert key in c, f"KnowledgeEntry dict missing key {key!r}"

    def test_escalation_event_schema(self):
        console = Console(file=StringIO())
        buf = StringIO()
        reporter = ProgressReporter(console=console, json_sink=buf)
        reporter.phase_escalated("phase_A", 3, ["motion_drift", "ctf_fit_quality"])
        events = [json.loads(l) for l in buf.getvalue().strip().splitlines() if l.strip()]
        esc = [e for e in events if e["type"] == "autoloop_escalation"]
        assert len(esc) == 1
        e = esc[0]
        assert e["phase"] == "phase_A"
        assert e["total_attempts"] == 3
        assert "motion_drift" in e["gates_failed"]
        assert "message" in e

    def test_in_memory_events_list(self):
        _, events_returned = self._run_minimal_reporter()
        # Also check via .events property
        console = Console(file=StringIO())
        buf = StringIO()
        reporter = ProgressReporter(console=console, json_sink=buf)
        ev = CryoEMQCEvaluator()
        qc = ev.evaluate_phase_A({"mean_total_drift_A": 20.0, "mean_per_frame_drift_A": 1.0,
                                   "mean_ctf_fit_quality": 0.88, "mean_astigmatism_A": 300.0})
        reporter.gate_results(qc)
        assert len(reporter.events) == 1
        assert reporter.events[0]["type"] == "autoloop_gate_results"


# ── 4. Full demo scenario outcomes ───────────────────────────────────────────

class TestDemoScenarios:

    def test_all_pass_scenario(self, tmpdir):
        result = run_scenario(
            "all_pass",
            output_dir=tmpdir / "all_pass",
            console=Console(file=StringIO()),
        )
        assert set(result["phases_passed"]) == {
            "phase_A", "phase_B", "phase_C", "phase_D", "phase_E"
        }
        assert result["phases_escalated"] == []
        assert result["total_attempts"] == 5

    def test_retry_then_pass_scenario(self, tmpdir):
        result = run_scenario(
            "retry_then_pass",
            output_dir=tmpdir / "retry",
            console=Console(file=StringIO()),
        )
        assert "phase_A" in result["phases_passed"]
        assert result["phases_escalated"] == []
        # Phase A required 2 attempts; others 1 each = 6 total
        assert result["total_attempts"] >= 6

    def test_escalation_scenario(self, tmpdir):
        result = run_scenario(
            "escalation",
            max_retries=2,
            output_dir=tmpdir / "esc",
            console=Console(file=StringIO()),
        )
        assert "phase_A" in result["phases_escalated"]
        # Other phases should still complete
        assert len(result["phases_passed"]) >= 3

    def test_membrane_profile_passes(self, tmpdir):
        result = run_scenario(
            "membrane_profile",
            qc_profile="cryoem_spa_membrane",
            output_dir=tmpdir / "membrane",
            console=Console(file=StringIO()),
        )
        assert "phase_A" in result["phases_passed"], (
            f"membrane profile should pass phase_A for 65Å drift; "
            f"escalated={result['phases_escalated']}"
        )


# ── 5. SSE event stream structure ─────────────────────────────────────────────

class TestSSEEventStream:
    """
    Validates the full event stream from a demo run matches the frontend contract
    defined in docs/20260416_CRYOEM_AUTOLOOP_ARCHITECTURE.md.
    """

    @pytest.fixture(autouse=True)
    def run_retry_scenario(self, tmpdir):
        self.result = run_scenario(
            "retry_then_pass",
            output_dir=tmpdir / "sse",
            console=Console(file=StringIO()),
        )
        self.events = self.result["events"]

    def test_event_stream_has_all_required_types(self):
        types = {e["type"] for e in self.events}
        required = {
            "autoloop_phase_start",
            "autoloop_running",
            "autoloop_gate_results",
            "autoloop_update",        # retry triggered
            "autoloop_phase_complete",
            "autoloop_complete",
        }
        missing = required - types
        assert not missing, f"Missing event types in stream: {missing}"

    def test_phase_start_events_cover_all_phases(self):
        starts = [e for e in self.events if e["type"] == "autoloop_phase_start"]
        phases_started = {e["phase"] for e in starts}
        assert phases_started == {"phase_A", "phase_B", "phase_C", "phase_D", "phase_E"}

    def test_autoloop_update_has_param_changes(self):
        """The retry event must report what parameter changed."""
        updates = [e for e in self.events if e["type"] == "autoloop_update"]
        assert len(updates) >= 1, "retry_then_pass should have at least one retry"
        u = updates[0]
        assert u["phase"] == "phase_A"
        # Must have remediations with param_changes
        assert "remediations" in u
        param_changing = [r for r in u["remediations"] if r.get("param_changes")]
        assert len(param_changing) >= 1

    def test_autoloop_update_has_citations_with_doi(self):
        updates = [e for e in self.events if e["type"] == "autoloop_update"]
        for u in updates:
            for r in u.get("remediations", []):
                for c in r.get("citations", []):
                    assert "paper_doi" in c and c["paper_doi"], (
                        "Each knowledge entry must have a paper_doi"
                    )

    def test_final_complete_event_has_summary(self):
        complete = [e for e in self.events if e["type"] == "autoloop_complete"]
        assert len(complete) == 1
        c = complete[0]
        assert "phases_passed" in c
        assert "phases_escalated" in c
        assert "total_attempts" in c
        assert "audit_path" in c

    def test_events_are_ordered_by_phase(self):
        """Phase A events must all appear before Phase B events."""
        phase_events = [
            e for e in self.events
            if e.get("phase") in {"phase_A", "phase_B"}
        ]
        phases_seen = [e["phase"] for e in phase_events]
        # Find last phase_A index and first phase_B index
        last_a = max((i for i, p in enumerate(phases_seen) if p == "phase_A"), default=-1)
        first_b = min((i for i, p in enumerate(phases_seen) if p == "phase_B"), default=len(phases_seen))
        assert last_a < first_b, "Phase A events must all complete before Phase B starts"

    def test_all_events_json_serialisable(self):
        for e in self.events:
            json.dumps(e)  # must not raise


if __name__ == "__main__":
    import subprocess
    sys.exit(subprocess.call(["python", "-m", "pytest", __file__, "-v"]))
