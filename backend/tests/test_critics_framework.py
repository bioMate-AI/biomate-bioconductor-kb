"""Interface-level tests for the generic Critic framework.

Covers the data model (Issue/Remediation/Evidence/Severity), RunContext construction
from the run contract, registry dispatch, and the two structural guardrails enforced
by the post-run hook:
  * cite-evidence-or-stay-silent (uncited issue -> suppressed, severity capped)
  * advisory-by-default + audited opt-in auto-apply

Pure Python, zero AWS / R / network. Run:
    cd backend && PYTHONPATH=lib python3.9 -m pytest tests/test_critics_framework.py -q
"""
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_LIB = ROOT / "backend" / "lib"
sys.path.insert(0, str(_LIB))

# The critics package is stdlib-only and must import cheaply. In a healthy env the
# real `import galaxy.ai.critics` works. In a minimal local env, galaxy/ai/__init__.py
# eagerly imports the heavy AI/scipy stack, which may be broken (unrelated to critics);
# fall back to a lightweight `galaxy.ai` namespace stub so the unit-under-test still
# imports in isolation. Healthy envs never hit the fallback, so the shared suite is
# not polluted.
try:  # noqa: SIM105
    import galaxy.ai.critics  # noqa: F401
except Exception:
    _stub = types.ModuleType("galaxy.ai")
    _stub.__path__ = [str(_LIB / "galaxy" / "ai")]
    sys.modules["galaxy.ai"] = _stub

from galaxy.ai.critics import (  # noqa: E402
    Critic, Issue, Remediation, Evidence, Severity, Provenance, RemediationKind,
    RunContext, OutputFile, CriticRegistry, run_critics,
)


# ── fixtures / helpers ────────────────────────────────────────────────────────

def _cited_ev():
    return Evidence(claim="rule", source="Some Guideline", doi="10.1/x", provenance=Provenance.GOLD)


class _CitedCritic(Critic):
    domain = "demo"
    critic_id = "demo.cited"

    def detect(self, ctx):
        return [Issue(
            critic_id=self.critic_id, code="demo_issue", title="demo issue",
            severity=Severity.WARNING, evidence=[_cited_ev()],
            metrics={"p_value": 0.01},
        )]

    def remediate(self, issue, ctx):
        return Remediation(
            issue_code=issue.code, kind=RemediationKind.ADD_COVARIATE,
            summary="do the thing", evidence=[_cited_ev()],
            params_delta={"formula": "y ~ x + z"},
        )


class _UncitedCritic(Critic):
    domain = "demo"
    critic_id = "demo.uncited"

    def detect(self, ctx):
        return [Issue(
            critic_id=self.critic_id, code="uncited_issue", title="uncited",
            severity=Severity.CRITICAL, evidence=[],  # no evidence
        )]

    def remediate(self, issue, ctx):
        return Remediation(issue_code=issue.code, kind=RemediationKind.FLAG, summary="flag only")


def _demo_ctx():
    return RunContext(run_id="r1", workflow_domain="demo")


# ── data model ────────────────────────────────────────────────────────────────

def test_issue_citation_flag():
    assert Issue("c", "x", "t", evidence=[_cited_ev()]).is_cited is True
    assert Issue("c", "x", "t", evidence=[]).is_cited is False
    assert Issue("c", "x", "t", evidence=[Evidence("y")]).is_cited is False  # uncited evidence


def test_severity_ordering():
    assert Severity.INFO.rank < Severity.ADVISORY.rank < Severity.WARNING.rank < Severity.CRITICAL.rank


def test_remediation_round_trips_to_dict():
    r = Remediation("x", RemediationKind.REFIT, "s", params_delta={"a": 1})
    d = r.to_dict()
    assert d["kind"] == "refit" and d["applied"] is False and d["params_delta"] == {"a": 1}


# ── RunContext from the contract ──────────────────────────────────────────────

def test_run_context_from_contract():
    design = {
        "run_id": "run-x", "workflow": "wf.nf", "workflow_domain": "survival",
        "inputs": {"data": "s3://b/x.csv"}, "parameters": {"alpha": 0.05},
        "design": {"formula": "Surv(t,s)~a", "covariates": ["a"], "group_sizes": {}},
    }
    manifest = {
        "run_id": "run-x", "workflow": "wf.nf", "workflow_domain": "survival",
        "files": [{"name": "survival_qc.json", "s3_uri": "s3://b/survival_qc.json",
                   "role": "qc", "extension": "json"}],
    }
    ctx = RunContext.from_contract(design, manifest)
    assert ctx.run_id == "run-x"
    assert ctx.workflow_domain == "survival"
    assert ctx.inputs == {"data": "s3://b/x.csv"}
    assert ctx.parameters == {"alpha": 0.05}
    assert ctx.find_artifact("survival_qc.json") is not None
    assert ctx.find_artifact("nonexistent.json") is None
    assert ctx.outputs_by_role("qc")[0].name == "survival_qc.json"


def test_run_context_loads_inline_and_loader_artifacts():
    # inline dict
    ctx = RunContext(run_id="r", inline_artifacts={"q.json": {"k": 1}})
    assert ctx.load_json("q.json") == {"k": 1}
    # loader path keyed by s3_uri
    loaded = {}

    def _loader(key):
        loaded["key"] = key
        return b'{"v": 2}'

    ctx2 = RunContext(
        run_id="r",
        outputs=[OutputFile(name="q.json", s3_uri="s3://b/q.json")],
        artifact_loader=_loader,
    )
    assert ctx2.load_json("q.json") == {"v": 2}
    assert loaded["key"] == "s3://b/q.json"  # prefers the s3_uri from the manifest


# ── registry dispatch ─────────────────────────────────────────────────────────

def test_registry_dispatch_by_context():
    reg = CriticRegistry()
    reg.register(_CitedCritic())
    reg.register(_UncitedCritic())
    applicable = reg.for_context(_demo_ctx())
    assert {c.critic_id for c in applicable} == {"demo.cited", "demo.uncited"}
    # a run from a different domain with no self-selecting critic → none apply
    other = reg.for_context(RunContext(run_id="r2", workflow_domain="genomics"))
    assert other == []


def test_applies_to_requires_artifact():
    class _NeedsArt(_CitedCritic):
        critic_id = "demo.needsart"
        required_artifacts = ["must_have.json"]

    reg = CriticRegistry()
    reg.register(_NeedsArt())
    # artifact absent → does not apply
    assert reg.for_context(_demo_ctx()) == []
    # artifact present (inline) → applies
    ctx = RunContext(run_id="r", workflow_domain="demo",
                     inline_artifacts={"must_have.json": {"ok": True}})
    assert [c.critic_id for c in reg.for_context(ctx)] == ["demo.needsart"]


# ── guardrail 1: cite-evidence-or-stay-silent ─────────────────────────────────

def test_uncited_issue_is_suppressed_and_capped():
    reg = CriticRegistry()
    reg.register(_UncitedCritic())
    report = run_critics(_demo_ctx(), registry=reg)
    assert len(report.findings) == 1
    f = report.findings[0]
    assert f.published is False                 # not surfaced as a gate
    assert f.issue.severity == Severity.ADVISORY  # CRITICAL capped to advisory
    assert report.gates == []                   # nothing published
    assert report.has_issues is False


def test_cited_issue_is_published_as_gate():
    reg = CriticRegistry()
    reg.register(_CitedCritic())
    report = run_critics(_demo_ctx(), registry=reg)
    assert len(report.findings) == 1 and report.findings[0].published is True
    assert len(report.gates) == 1
    gate_row, value, threshold, passes, level, msg = report.gates[0]
    assert gate_row == "critic_demo_issue" and passes is False and level == "FAIL"


def test_require_citation_false_publishes_uncited():
    reg = CriticRegistry()
    reg.register(_UncitedCritic())
    report = run_critics(_demo_ctx(), registry=reg, require_citation=False)
    assert report.findings[0].published is True


# ── guardrail 2: advisory-by-default + audited auto-apply ─────────────────────

def test_remediation_advisory_by_default():
    reg = CriticRegistry()
    reg.register(_CitedCritic())
    report = run_critics(_demo_ctx(), registry=reg)  # auto_apply defaults False
    rem = report.findings[0].remediation
    assert rem.applied is False and rem.audit == {}


def test_auto_apply_requires_allowlisted_kind_and_is_audited():
    reg = CriticRegistry()
    reg.register(_CitedCritic())
    # auto_apply on but kind not allowlisted → still advisory
    r1 = run_critics(_demo_ctx(), registry=reg, auto_apply=True, auto_apply_kinds=())
    assert r1.findings[0].remediation.applied is False
    # kind allowlisted + cited → applied + audit trail populated
    r2 = run_critics(_demo_ctx(), registry=reg, auto_apply=True,
                     auto_apply_kinds=(RemediationKind.ADD_COVARIATE,))
    rem = r2.findings[0].remediation
    assert rem.applied is True
    assert rem.audit["critic_id"] == "demo.cited"
    assert rem.audit["params_delta"] == {"formula": "y ~ x + z"}
    assert rem.audit["evidence"]  # cited evidence recorded


def test_transport_callbacks_receive_published_findings():
    reg = CriticRegistry()
    reg.register(_CitedCritic())
    events = []
    gates_published = []
    stored = {}
    run_critics(
        _demo_ctx(), registry=reg,
        emit=lambda e, d: events.append((e, d)),
        publish_gates=lambda g: gates_published.extend(g),
        store_suggestions=lambda inv, doc: stored.update({inv: doc}),
    )
    event_types = {e for e, _ in events}
    assert "autoloop_gate_results" in event_types and "autoloop_update" in event_types
    assert len(gates_published) == 1
    assert "r1" in stored and stored["r1"]["source"] == "critic_layer"
