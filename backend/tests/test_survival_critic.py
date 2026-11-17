"""Stream-3 migration test: SurvivalConfoundingCritic + SurvivalPHCritic reproduce
the live survival self-correction behaviour from the RUN CONTRACT (survival_qc.json +
design.json + results_manifest.json) — NOT from the embedded cox.nf R.

The fixture mirrors the live Stream-3 case:
  * naive primary HR 0.817  ->  adjusted 0.806
  * omitted confounders: ECOG (p=.003), liver_mets (p=.011)
  * proportional-hazards violation on ECOG (global Schoenfeld p=.012) -> time-transform

Run:
    cd backend && PYTHONPATH=lib python3.9 -m pytest tests/test_survival_critic.py -q
"""
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_LIB = ROOT / "backend" / "lib"
sys.path.insert(0, str(_LIB))

# See test_critics_framework.py for the rationale: real import first, lightweight
# galaxy.ai namespace stub only when the heavy parent-init is broken locally.
try:  # noqa: SIM105
    import galaxy.ai.critics  # noqa: F401
except Exception:
    _stub = types.ModuleType("galaxy.ai")
    _stub.__path__ = [str(_LIB / "galaxy" / "ai")]
    sys.modules["galaxy.ai"] = _stub

from galaxy.ai.critics import (  # noqa: E402
    RunContext, RemediationKind, Severity, run_critics_from_run_meta, get_registry,
)
from galaxy.ai.critics.critics.survival import (  # noqa: E402
    SurvivalConfoundingCritic, SurvivalPHCritic,
)


# ── live Stream-3 fixture (the survival_qc.json the cox.nf emitter produces) ───

SURVIVAL_QC = {
    "process": "BIOC_SURVIVAL_COX_PROPORTIONAL_HAZARDS_REGRESSION",
    "domain": "survival",
    "primary_covariate": "treatment",
    "naive_primary_hr": 0.817,
    "adjusted_primary_hr": 0.806,
    "schoenfeld_global_p": 0.012,
    "ph_violating_covariates": ["ecog"],
    "omitted_confounders": [
        {"name": "ecog", "hr": 1.92, "p": 0.003},
        {"name": "liver_mets", "hr": 2.14, "p": 0.011},
    ],
}

DESIGN_JSON = {
    "kind": "design", "run_id": "run-stream3",
    "workflow": "cox_proportional_hazards_regression.nf",
    "nextflow_path": "subworkflows/bioconductor/survival/cox_proportional_hazards_regression.nf",
    "workflow_domain": "survival",
    "inputs": {"input_data": "s3://biomate/run-stream3/patient_clinical_data.csv"},
    "parameters": {},
    "design": {"formula": None, "covariates": [], "group_sizes": {}},
}

RESULTS_MANIFEST = {
    "kind": "results_manifest", "run_id": "run-stream3",
    "workflow": "cox_proportional_hazards_regression.nf",
    "workflow_domain": "survival",
    "files": [
        {"name": "survival_qc.json", "s3_uri": "s3://biomate/run-stream3/survival_qc.json",
         "role": "qc", "extension": "json"},
        {"name": "cox_coefficients.csv", "s3_uri": "s3://biomate/run-stream3/cox_coefficients.csv",
         "role": "table", "extension": "csv"},
        {"name": "cox_zph_test.csv", "s3_uri": "s3://biomate/run-stream3/cox_zph_test.csv",
         "role": "table", "extension": "csv"},
    ],
}


def _ctx():
    return RunContext.from_contract(
        DESIGN_JSON, RESULTS_MANIFEST,
        inline_artifacts={"survival_qc.json": SURVIVAL_QC},
    )


# ── SurvivalConfoundingCritic ─────────────────────────────────────────────────

def test_confounding_detect_identifies_both_confounders():
    issues = SurvivalConfoundingCritic().detect(_ctx())
    assert len(issues) == 1
    iss = issues[0]
    assert iss.code == "omitted_confounder"
    assert iss.severity == Severity.WARNING
    assert set(iss.subjects) == {"ecog", "liver_mets"}
    assert iss.metrics["naive_hr"] == 0.817
    assert iss.metrics["adjusted_hr"] == 0.806
    assert iss.metrics["hr_shift"] == -0.011
    assert iss.is_cited  # grounded in survival.adjust_confounders (GOLD, DOI)


def test_confounding_remediation_is_adjusted_refit_with_naive_vs_corrected():
    critic = SurvivalConfoundingCritic()
    iss = critic.detect(_ctx())[0]
    rem = critic.remediate(iss, _ctx())
    assert rem.kind == RemediationKind.ADD_COVARIATE
    assert rem.naive["hazard_ratio"] == 0.817
    assert rem.corrected["hazard_ratio"] == 0.806
    assert set(rem.corrected["covariates_added"]) == {"ecog", "liver_mets"}
    # corrected formula adjusts the primary covariate for both confounders
    assert "treatment" in rem.params_delta["formula"]
    assert "ecog" in rem.params_delta["formula"] and "liver_mets" in rem.params_delta["formula"]
    assert rem.applied is False  # advisory by default


def test_confounding_silent_when_no_significant_confounder():
    qc = dict(SURVIVAL_QC, omitted_confounders=[{"name": "sex", "hr": 1.05, "p": 0.4}])
    ctx = RunContext.from_contract(DESIGN_JSON, RESULTS_MANIFEST,
                                   inline_artifacts={"survival_qc.json": qc})
    assert SurvivalConfoundingCritic().detect(ctx) == []


# ── SurvivalPHCritic ──────────────────────────────────────────────────────────

def test_ph_detect_flags_schoenfeld_violation():
    issues = SurvivalPHCritic().detect(_ctx())
    assert len(issues) == 1
    iss = issues[0]
    assert iss.code == "ph_violation"
    assert iss.subjects == ["ecog"]
    assert iss.metrics["schoenfeld_global_p"] == 0.012
    assert iss.is_cited


def test_ph_remediation_proposes_time_transform():
    critic = SurvivalPHCritic()
    iss = critic.detect(_ctx())[0]
    rem = critic.remediate(iss, _ctx())
    assert rem.kind == RemediationKind.TIME_TRANSFORM
    assert "ecog" in rem.params_delta["time_transform"]
    assert "ecog" in rem.params_delta["strata"]


def test_ph_silent_when_assumption_holds():
    qc = dict(SURVIVAL_QC, schoenfeld_global_p=0.42, ph_violating_covariates=[])
    ctx = RunContext.from_contract(DESIGN_JSON, RESULTS_MANIFEST,
                                   inline_artifacts={"survival_qc.json": qc})
    assert SurvivalPHCritic().detect(ctx) == []


# ── end-to-end through the hook + registry ────────────────────────────────────

def test_survival_critics_registered_in_default_registry():
    reg = get_registry()
    ids = {c.critic_id for c in reg.all()}
    assert {"survival.confounding", "survival.proportional_hazards"} <= ids


def test_full_hook_publishes_both_findings_from_run_meta():
    run_meta = {
        "run_id": "run-stream3",
        "design": DESIGN_JSON,
        "results_manifest": RESULTS_MANIFEST,
    }
    # artifact_loader stands in for the S3 reader on the Batch completion path.
    import json

    def _loader(key):
        if key.endswith("survival_qc.json"):
            return json.dumps(SURVIVAL_QC).encode("utf-8")
        return None

    report = run_critics_from_run_meta(run_meta, artifact_loader=_loader)
    published = [f for f in report.findings if f.published]
    codes = {f.issue.code for f in published}
    assert codes == {"omitted_confounder", "ph_violation"}
    assert len(report.gates) == 2
    # both remediations present, advisory
    assert all(f.remediation is not None and f.remediation.applied is False for f in published)
    # the naive-vs-corrected headline survives into the published report
    conf = next(f for f in published if f.issue.code == "omitted_confounder")
    assert conf.remediation.naive["hazard_ratio"] == 0.817
    assert conf.remediation.corrected["hazard_ratio"] == 0.806
