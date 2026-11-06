"""CPU unit tests for the Track-A loop skeleton — generate -> A3 gate -> A1 verify -> A2 select
-> A4 pair-emit -> learn. Pure logic on MOCK property vectors: no GPU, no AWS, no RDKit, no
training data, no network. Proves the interfaces COMPOSE and that fail-safe holds at every seam.

Covers:
  * peptide_gate (A3): hard floor/ceiling, validity reject, fail-open on missing, cost accounting,
    and that it drives verify's ``only=`` cheap subset.
  * dpo_pairs (A4): schema/TRL record shape, verify_select stream, activity+expert exemplar streams,
    dedup + symmetric-conflict drop, provenance envelope.
  * peptide_loop: full chain composes with injected mock generate/gate/verify/select/emit/learn,
    the loop summary aggregates, and one broken stage degrades gracefully (fail-safe).

Run: ``python -m pytest test_peptide_loop.py``  (or ``python test_peptide_loop.py`` for a smoke run)
"""
import importlib.util
import sys
from pathlib import Path

import pytest

_HERE = Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, _HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod  # dataclass introspection needs the module registered
    spec.loader.exec_module(mod)
    return mod


gate_mod = _load("peptide_gate")
dpo_mod = _load("dpo_pairs")
loop_mod = _load("peptide_loop")


# ============================================================ mock A1 building blocks
class MockPV:
    """Stand-in for peptide_verify.PropertyValue (duck-typed: .value/.provenance/.ok)."""
    def __init__(self, value=None, provenance="unavailable", uncertainty=None):
        self.value = value
        self.provenance = provenance
        self.uncertainty = uncertainty

    def ok(self):
        return self.value is not None


class MockProps:
    """Stand-in for peptide_verify.PeptideProperties (duck-typed: .scored_fields())."""
    def __init__(self, identifier, sequence=None, smiles=None,
                 dG=None, perm=None, sa=None, safety=None,
                 prov=("measured", "predicted", "proxy", "proxy")):
        self.identifier = identifier
        self.sequence = sequence
        self.smiles = smiles
        pdG, pperm, psa, psafe = prov
        self.affinity_dG = MockPV(dG, pdG if dG is not None else "unavailable")
        self.permeability = MockPV(perm, pperm if perm is not None else "unavailable")
        self.synthetic_accessibility = MockPV(sa, psa if sa is not None else "unavailable")
        self.safety = MockPV(safety, psafe if safety is not None else "unavailable")

    def scored_fields(self):
        return {"affinity_dG": self.affinity_dG, "permeability": self.permeability,
                "synthetic_accessibility": self.synthetic_accessibility, "safety": self.safety}


# map verify field names -> MockProps ctor kwargs
_FIELD_KW = {"affinity_dG": "dG", "permeability": "perm",
             "synthetic_accessibility": "sa", "safety": "safety"}


def _mock_cheap_verify(fields_by_id):
    """Build a gate verify_fn(seq, smiles, identifier, only) that returns a MockProps with ONLY the
    requested cheap fields populated — proves the gate uses verify's ``only=`` subset. Keys in
    ``fields_by_id`` use verify field names (permeability/synthetic_accessibility)."""
    def _fn(seq, smiles, identifier, only):
        src = fields_by_id.get(identifier, {})
        kw = {_FIELD_KW[k]: src.get(k) for k in only if k in _FIELD_KW}
        return MockProps(identifier, sequence=seq, smiles=smiles, **kw)
    return _fn


# ============================================================ A3 gate
def test_gate_floor_and_ceiling():
    fields = {
        "good": {"permeability": -5.0, "synthetic_accessibility": 3.0},
        "low_perm": {"permeability": -9.0, "synthetic_accessibility": 3.0},   # below floor
        "hard": {"permeability": -5.0, "synthetic_accessibility": 8.0},       # above SA ceiling
    }
    vfn = _mock_cheap_verify(fields)
    pool = [{"identifier": i, "seq": "AAAA"} for i in fields]
    th = gate_mod.GateThresholds(permeability_floor=-7.0, sa_ceiling=6.5, require_validity=False)
    res = gate_mod.gate_candidates(pool, th, verify_fn=vfn)
    assert set(res.passed_ids) == {"good"}
    assert set(res.rejected_ids) == {"low_perm", "hard"}
    # cost accounting: rejects skip the expensive verify
    assert res.n_expensive_verify_saved == 2
    # gate only asked for the cheap fields, never affinity_dG
    assert res.verify_fields_used == ["permeability", "synthetic_accessibility"]


def test_gate_fail_open_on_missing():
    """A missing cheap field must NOT auto-reject (fail-safe): unknown != failed."""
    fields = {"unknown": {}}  # verify returns None for both cheap fields
    vfn = _mock_cheap_verify(fields)
    pool = [{"identifier": "unknown", "seq": "AAAA"}]
    th = gate_mod.GateThresholds(require_validity=False)  # on_missing defaults to "pass"
    res = gate_mod.gate_candidates(pool, th, verify_fn=vfn)
    assert res.passed_ids == ["unknown"]


def test_gate_reject_on_missing_when_conservative():
    fields = {"unknown": {}}
    vfn = _mock_cheap_verify(fields)
    pool = [{"identifier": "unknown", "seq": "AAAA"}]
    th = gate_mod.GateThresholds(require_validity=False,
                                 permeability_on_missing="reject", sa_on_missing="pass")
    res = gate_mod.gate_candidates(pool, th, verify_fn=vfn)
    assert res.rejected_ids == ["unknown"]


def test_gate_verify_raise_is_failsafe():
    """If the cheap verify itself blows up, the gate must not crash — it judges on missing policy."""
    def _boom(seq, smiles, identifier, only):
        raise RuntimeError("scorer exploded")
    pool = [{"identifier": "x", "seq": "AAAA"}]
    th = gate_mod.GateThresholds(require_validity=False)  # fail-open
    res = gate_mod.gate_candidates(pool, th, verify_fn=_boom)
    assert res.passed_ids == ["x"]  # degraded to missing -> fail-open


# ============================================================ A4 pair emitter
class MockSelection:
    """Stand-in for peptide_select.SelectionResult (fields the emitter reads)."""
    def __init__(self, selected, pareto_front, hvi):
        self.selected = selected
        self.pareto_front = pareto_front
        self.hvi = hvi


def test_pairs_from_selection_verify_select_stream():
    pool = [
        MockProps("win", smiles="CCO", dG=-40.0, perm=-4.0, sa=3.0, safety=0.9),
        MockProps("lose", smiles="CCC", dG=-10.0, perm=-8.0, sa=8.0, safety=0.2),
        MockProps("gated", smiles="CCN", dG=-20.0, perm=-9.0, sa=3.0, safety=0.5),
    ]
    sel = MockSelection(selected=["win"], pareto_front=["win"], hvi={"win": 0.8, "lose": 0.1})
    pairs = dpo_mod.pairs_from_selection(pool, sel, prompt="targetX",
                                         gate_rejected_ids=["gated"])
    # win should be chosen over both the gated (clean neg) and the dominated (lose)
    keys = {(p.chosen_id, p.rejected_id) for p in pairs}
    assert ("win", "gated") in keys
    assert ("win", "lose") in keys
    # gate-rejected negative is the clean (non-weak) one
    clean = [p for p in pairs if p.rejected_id == "gated"][0]
    assert clean.weak is False
    assert clean.prompt == "targetX"
    # margin computed from HVI gap where available
    m = [p for p in pairs if p.rejected_id == "lose"][0]
    assert m.margin == pytest.approx(0.7)
    # TRL record shape
    rec = clean.to_trl_record()
    assert set(rec) == {"prompt", "chosen", "rejected"}
    assert rec["chosen"] == "CCO"  # SMILES preferred as representation


def test_emit_pairs_all_streams_and_conflict_drop():
    pool = [MockProps("win", smiles="CCO", dG=-40, perm=-4, sa=3, safety=0.9),
            MockProps("lose", smiles="CCC", dG=-10, perm=-8, sa=8, safety=0.2)]
    sel = MockSelection(selected=["win"], pareto_front=["win"], hvi={"win": 0.8, "lose": 0.1})

    activity = [dpo_mod.ExemplarPair(chosen="C1CCCCC1", rejected="CC", source="ChEMBL",
                                     chosen_provenance="measured", rejected_provenance="measured")]
    # expert pair that CONTRADICTS the activity pair (reversed) -> must drop BOTH
    expert = [dpo_mod.ExemplarPair(chosen="CC", rejected="C1CCCCC1", source="SureChEMBL", weak=True)]

    ps = dpo_mod.emit_pairs(verified_pool=pool, selection_result=sel,
                            gate_rejected_ids=[], activity_exemplars=activity,
                            expert_exemplars=expert)
    counts = ps.stream_counts()
    # verify_select produced at least one pair; the activity/expert conflict pair pair was dropped
    assert counts.get(dpo_mod.STREAM_VERIFY_SELECT, 0) >= 1
    assert len(ps.dropped_conflicts) == 1
    assert dpo_mod.STREAM_ACTIVITY not in counts  # both sides of the conflict removed
    assert dpo_mod.STREAM_EXPERT not in counts
    # TRL export is clean triples
    for rec in ps.to_trl_records():
        assert set(rec) == {"prompt", "chosen", "rejected"}


def test_emit_pairs_dedup_and_weak_drop():
    a = dpo_mod.ExemplarPair(chosen="CCO", rejected="CC", source="ExCAPE")
    dup = dpo_mod.ExemplarPair(chosen="CCO", rejected="CC", source="ExCAPE")
    weak = dpo_mod.ExemplarPair(chosen="CCN", rejected="CO", source="patent_only", weak=True)
    ps = dpo_mod.emit_pairs(activity_exemplars=[a, dup, weak])
    assert ps.n_duplicates_merged == 1
    ps2 = dpo_mod.emit_pairs(activity_exemplars=[a, weak], drop_weak=True)
    assert all(not p.weak for p in ps2.pairs)


# ============================================================ full loop composition
def test_full_loop_composes_with_mocks():
    """generate -> gate -> verify -> select -> emit -> learn, all mocked, proves the chain wires."""
    pool = [{"identifier": f"p{i}", "seq": "AAAA", "smiles": s}
            for i, s in enumerate(["CCO", "CCC", "CCN", "CCCC"])]

    # mock cheap verify for the gate: p1 fails the perm floor
    cheap_fields = {
        "p0": {"permeability": -4.0, "synthetic_accessibility": 3.0},
        "p1": {"permeability": -9.0, "synthetic_accessibility": 3.0},   # gated out
        "p2": {"permeability": -5.0, "synthetic_accessibility": 4.0},
        "p3": {"permeability": -5.5, "synthetic_accessibility": 3.5},
    }
    gate_verify = _mock_cheap_verify(cheap_fields)

    def gate_fn(pool_, thresholds):
        return gate_mod.gate_candidates(pool_, thresholds, verify_fn=gate_verify)

    # mock full verify (A1): returns full MockProps vectors for survivors
    full = {
        "p0": dict(dG=-40, perm=-4.0, sa=3.0, safety=0.9),
        "p2": dict(dG=-25, perm=-5.0, sa=4.0, safety=0.6),
        "p3": dict(dG=-30, perm=-5.5, sa=3.5, safety=0.7),
    }

    def verify_fn(survivors, **kw):
        return [MockProps(c["identifier"], sequence=c.get("seq"), smiles=c.get("smiles"),
                          **full[c["identifier"]]) for c in survivors]

    cfg = loop_mod.LoopConfig(
        n_select=2, rounds=1,
        generator=loop_mod.PoolGenerator(pool),
        gate_fn=gate_fn,
        verify_fn=verify_fn,
        gate_thresholds=gate_mod.GateThresholds(permeability_floor=-7.0, require_validity=False),
    )
    res = loop_mod.run_loop(cfg)

    assert len(res.rounds) == 1
    rd = res.rounds[0]
    assert rd.n_generated == 4
    assert rd.n_gate_survivors == 3            # p1 gated out
    assert rd.n_expensive_verify_saved == 1    # p1 never hit the expensive verify
    assert len(rd.verified_ids) == 3
    assert len(rd.selected_ids) == 2           # A2 picked a batch of 2 from the 3 survivors
    assert rd.n_pairs_emitted >= 1             # A4 emitted at least one preference pair
    # summary aggregation
    assert res.summary["total_expensive_verify_saved"] == 1
    assert res.summary["total_selected"] == 2
    # provenance log ordered generate->gate->verify->select->emit->learn
    joined = " | ".join(rd.provenance)
    for stage in ["generate", "gate[A3]", "verify[A1]", "select[A2]", "emit[A4]", "learn"]:
        assert stage in joined


def test_loop_failsafe_empty_pool():
    """Empty generator pool: the loop must not crash; it records an empty round."""
    cfg = loop_mod.LoopConfig(generator=loop_mod.PoolGenerator([]), rounds=1)
    res = loop_mod.run_loop(cfg)
    rd = res.rounds[0]
    assert rd.n_generated == 0
    assert rd.n_gate_survivors == 0
    assert rd.selected_ids == []
    assert rd.n_pairs_emitted == 0


def test_frozen_checkpoint_generator_is_a_seam():
    """The frozen epoch-221 generator is a documented seam: it raises unless a real sample_fn is
    injected (the GPU sampler), and a drop-in sample_fn satisfies the same interface."""
    gen = loop_mod.FrozenCheckpointGenerator()
    with pytest.raises(NotImplementedError):
        gen.generate({}, 4)
    # inject a fake sampler -> same interface works
    gen2 = loop_mod.FrozenCheckpointGenerator(
        sample_fn=lambda ctx, n: [{"identifier": f"s{i}", "seq": "GG"} for i in range(n)])
    assert len(gen2.generate({}, 3)) == 3


if __name__ == "__main__":
    import subprocess
    sys.exit(subprocess.call([sys.executable, "-m", "pytest", __file__, "-q"]))
