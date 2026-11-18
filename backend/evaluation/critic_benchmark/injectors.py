"""
Error-injectors — the heart of the benchmark.

Each injector takes a *clean* run contract (design.json + results_manifest + the
per-class QC artifact a critic reads) and returns a *corrupted* contract carrying a
**known ground-truth label**. The matched clean contract is the negative. Where the
archetype has a classic look-alike that must NOT fire, we also emit a **hard negative**
(a mediator that should not be adjusted; a balanced covariate that is not a confounder).

Archetypes (each targets exactly one critic; the item carries ONLY that critic's
artifact, so only the target critic's ``applies_to`` passes):

  design.confounding      -> survival.confounding                (REAL critic)
      positive       : a genuine omitted prognostic confounder (CIE > 10%)
      hard_negative  : an omitted MEDIATOR — adjusting for it is the WRONG fix
                       (Table-2 fallacy); the real critic WILL fire here, and the
                       benchmark measures that as a false alarm + harmful remediation.
  design.batch_imbalance  -> rnaseq.imbalanced_confounding        (stub, correct)
      positive       : batch collinear with condition (validity threat)
      hard_negative  : a BALANCED covariate (not a confounder) — must NOT fire
  power.epv               -> power.epv                           (REAL, WS2)
      positive       : events-per-variable < 10 (drop replicates)
      hard_negative  : EPV just above the floor (must NOT fire — no over-flagging)
  qc.threshold            -> qc.metric_floor                      (stub)
      positive       : a QC metric corrupted below its floor
  output.presence         -> output.presence                     (REAL, WS2)
      positive       : the primary result output dropped from the manifest

Ground-truth per item:
  should_fire      — the target critic SHOULD raise a published issue (positives only)
  harmful_if_fires — if the critic fires on this (clean/hard-negative) item, the
                     remediation is harmful (collider/mediator adjustment, false CRITICAL)

Determinism: every numeric knob is a pure function of (archetype, label, index), so the
generated set is byte-stable across runs and machines.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional


# ─────────────────────────────────────────────────────────────────────────────
# Archetype metadata (also consumed by the scorer / acceptance gates)
# ─────────────────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class ArchetypeSpec:
    name: str
    target_critic: str          # critic_id expected to (not) fire
    expected_code: str          # the Issue.code the target critic emits when firing
    clinical: bool              # clinical/patient context (governance demotion)
    governance: str             # 'deterministic_advisory' | 'deterministic_auto_apply'
    has_hard_negative: bool


ARCHETYPES: Dict[str, ArchetypeSpec] = {
    "design.confounding": ArchetypeSpec(
        "design.confounding", "survival.confounding", "omitted_confounder",
        clinical=True, governance="deterministic_advisory", has_hard_negative=True),
    "design.batch_imbalance": ArchetypeSpec(
        "design.batch_imbalance", "rnaseq.imbalanced_confounding",
        "batch_confounded_with_condition",
        clinical=False, governance="deterministic_advisory", has_hard_negative=True),
    "power.epv": ArchetypeSpec(
        "power.epv", "power.epv", "low_epv",
        clinical=False, governance="deterministic_advisory", has_hard_negative=True),
    "qc.threshold": ArchetypeSpec(
        "qc.threshold", "qc.metric_floor", "qc_below_floor",
        clinical=False, governance="deterministic_advisory", has_hard_negative=False),
    "output.presence": ArchetypeSpec(
        "output.presence", "output.presence", "missing_expected_outputs",
        clinical=False, governance="deterministic_advisory", has_hard_negative=False),
}


# ─────────────────────────────────────────────────────────────────────────────
# Contract scaffolding helpers
# ─────────────────────────────────────────────────────────────────────────────

def _manifest(files: List[Dict[str, Any]], workflow: str, domain: str) -> Dict[str, Any]:
    return {"workflow": workflow, "workflow_domain": domain, "files": files}


def _file(name: str, role: str) -> Dict[str, Any]:
    ext = name.rsplit(".", 1)[-1] if "." in name else ""
    return {"name": name, "role": role, "extension": ext, "s3_uri": f"s3://bench/{name}"}


# ─────────────────────────────────────────────────────────────────────────────
# 1. design.confounding  (survival.confounding — REAL critic)
# ─────────────────────────────────────────────────────────────────────────────

def _survival_contract(qc: Dict[str, Any], formula: str) -> Dict[str, Any]:
    return {
        "design": {
            "workflow": "cox_proportional_hazards_regression",
            "workflow_domain": "survival",
            "design": {"formula": formula, "covariates": ["arm"], "group_sizes": {"treated": 120, "control": 118}},
            "inputs": {"clinical": "clinical.csv"},
            "parameters": {},
        },
        "manifest": _manifest([_file("survival_qc.json", "qc"),
                               _file("cox_coefficients.csv", "table")],
                              "cox_proportional_hazards_regression", "survival"),
        "inline_artifacts": {"survival_qc.json": qc},
    }


def confounding_clean(i: int) -> Dict[str, Any]:
    """Negative: an omitted covariate that is NOT significant (p >= 0.05)."""
    p = round(0.10 + 0.05 * (i % 10), 4)             # 0.10 .. 0.55, never significant
    qc = {
        "primary_covariate": "arm",
        "naive_primary_hr": 0.81,
        "adjusted_primary_hr": 0.81,
        "omitted_confounders": [{"name": "age", "p": p, "role": "covariate"}],
        "schoenfeld_global_p": 0.42,
        "ph_violating_covariates": [],
    }
    return _survival_contract(qc, "Surv(time, status) ~ arm")


def confounding_positive(i: int) -> Dict[str, Any]:
    """Positive (omit-a-known-confounder): a genuine prognostic confounder, p<0.05,
    with a change-in-estimate > 10% (ECOG / liver-metastasis style)."""
    p = round(0.001 + 0.004 * (i % 10), 4)            # 0.001 .. 0.037, all significant
    naive = 0.82
    adjusted = round(naive * (1.0 - (0.12 + 0.01 * (i % 5))), 4)  # CIE 12-16%
    name = ["ecog_status", "liver_metastasis", "baseline_ldh", "prior_therapy"][i % 4]
    qc = {
        "primary_covariate": "arm",
        "naive_primary_hr": naive,
        "adjusted_primary_hr": adjusted,
        "omitted_confounders": [{"name": name, "p": p, "role": "confounder"}],
        "schoenfeld_global_p": 0.33,
        "ph_violating_covariates": [],
    }
    return _survival_contract(qc, "Surv(time, status) ~ arm")


def confounding_hard_negative(i: int) -> Dict[str, Any]:
    """Hard negative (mediator): an omitted covariate strongly associated with the
    outcome, p<0.05 — BUT it is a MEDIATOR on the causal path from treatment to
    outcome. Adjusting for it blocks the causal effect (Table-2 fallacy) and is the
    WRONG remediation. Correct verdict: do NOT fire. The real p<0.05-only critic will
    fire anyway — the benchmark measures that as a false alarm + harmful remediation."""
    p = round(0.0005 + 0.002 * (i % 10), 4)
    name = ["tumor_response", "on_treatment_biomarker_drop", "dose_intensity"][i % 3]
    qc = {
        "primary_covariate": "arm",
        "naive_primary_hr": 0.80,
        "adjusted_primary_hr": 0.93,          # "adjusting" moves HR toward null — bias
        "omitted_confounders": [{"name": name, "p": p, "role": "mediator"}],
        "schoenfeld_global_p": 0.40,
        "ph_violating_covariates": [],
    }
    return _survival_contract(qc, "Surv(time, status) ~ arm")


# ─────────────────────────────────────────────────────────────────────────────
# 2. design.batch_imbalance  (rnaseq.imbalanced_confounding — stub)
# ─────────────────────────────────────────────────────────────────────────────

def _rnaseq_contract(batch_qc: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "design": {
            "workflow": "differential_expression_deseq2",
            "workflow_domain": "rnaseq",
            "design": {"formula": "~condition", "covariates": ["condition"], "group_sizes": {"treated": 6, "control": 6}},
            "inputs": {"counts": "counts.tsv", "samplesheet": "samplesheet.csv"},
            "parameters": {},
        },
        "manifest": _manifest([_file("batch_qc.json", "qc"),
                               _file("deseq2_results.csv", "table")],
                              "differential_expression_deseq2", "rnaseq"),
        "inline_artifacts": {"batch_qc.json": batch_qc},
    }


def batch_clean(i: int) -> Dict[str, Any]:
    """Negative: batch is balanced across condition (low association)."""
    assoc = round(0.05 + 0.03 * (i % 8), 4)           # 0.05 .. 0.26
    qc = {"covariates": [{"name": "batch", "association_with_condition": assoc, "in_formula": False},
                         {"name": "sex", "association_with_condition": round(assoc / 2, 4), "in_formula": False}]}
    return _rnaseq_contract(qc)


def batch_positive(i: int) -> Dict[str, Any]:
    """Positive (inject-batch-imbalance): batch collinear with condition, not in formula."""
    assoc = round(0.85 + 0.014 * (i % 10), 4)         # 0.85 .. 0.98
    qc = {"covariates": [{"name": "batch", "association_with_condition": assoc, "in_formula": False},
                         {"name": "sex", "association_with_condition": 0.12, "in_formula": False}]}
    return _rnaseq_contract(qc)


def batch_hard_negative(i: int) -> Dict[str, Any]:
    """Hard negative (balanced covariate that is NOT a confounder): a covariate that
    looks important but is balanced across condition — omitting it costs precision, not
    validity. Must NOT fire (balanced != confounder)."""
    assoc = round(0.10 + 0.02 * (i % 8), 4)           # 0.10 .. 0.24  (balanced)
    qc = {"covariates": [{"name": "rin_bin", "association_with_condition": assoc, "in_formula": False},
                         {"name": "library_prep_day", "association_with_condition": round(assoc + 0.03, 4), "in_formula": False}]}
    return _rnaseq_contract(qc)


# ─────────────────────────────────────────────────────────────────────────────
# 3. power.epv  (power.events_per_variable — stub WS2)
# ─────────────────────────────────────────────────────────────────────────────

def _power_contract(n_events: int, n_cov: int) -> Dict[str, Any]:
    # Design facts live in the design block (where WS1 populates them and the real
    # power.epv critic reads them first) AND in a design_qc.json fallback the critic
    # also recognises — exactly the shape a real Cox run emits.
    return {
        "design": {
            "workflow": "cox_proportional_hazards_regression",
            "workflow_domain": "survival",
            "design": {"formula": "Surv(time, status) ~ arm + age + sex",
                       "covariates": ["arm", "age", "sex"],
                       "n_events": n_events, "n_covariates": n_cov,
                       "group_sizes": {}},
            "inputs": {"clinical": "clinical.csv"},
            "parameters": {},
        },
        "manifest": _manifest([_file("design_qc.json", "qc")],
                              "cox_proportional_hazards_regression", "survival"),
        "inline_artifacts": {"design_qc.json": {"n_events": n_events, "n_covariates": n_cov}},
    }


def epv_clean(i: int) -> Dict[str, Any]:
    """Negative: comfortably powered (EPV >> 10)."""
    n_cov = 3 + (i % 3)
    n_events = n_cov * (25 + i % 10)                  # EPV ~25-35
    return _power_contract(n_events, n_cov)


def epv_positive(i: int) -> Dict[str, Any]:
    """Positive (drop-replicates-below-EPV): EPV < 10."""
    n_cov = 4 + (i % 4)
    n_events = max(n_cov, int(n_cov * (2 + (i % 5) * 0.8)))  # EPV ~2-5.2
    return _power_contract(n_events, n_cov)


def epv_hard_negative(i: int) -> Dict[str, Any]:
    """Hard negative: EPV just above the floor (10.x) — must NOT fire (no over-flagging
    at the boundary)."""
    n_cov = 4 + (i % 3)
    n_events = int(round(n_cov * (10.2 + 0.1 * (i % 5))))    # EPV 10.2-10.6
    return _power_contract(n_events, n_cov)


# ─────────────────────────────────────────────────────────────────────────────
# 4. qc.threshold  (qc.metric_floor — stub)
# ─────────────────────────────────────────────────────────────────────────────

def _qc_contract(metrics: List[Dict[str, Any]]) -> Dict[str, Any]:
    return {
        "design": {
            "workflow": "nfcore_rnaseq",
            "workflow_domain": "rnaseq",
            "design": {"formula": None, "covariates": [], "group_sizes": {}},
            "inputs": {"samplesheet": "samplesheet.csv"},
            "parameters": {},
        },
        "manifest": _manifest([_file("qc_metrics.json", "qc"),
                               _file("multiqc_report.html", "report")],
                              "nfcore_rnaseq", "rnaseq"),
        "inline_artifacts": {"qc_metrics.json": {"metrics": metrics}},
    }


def qc_clean(i: int) -> Dict[str, Any]:
    """Negative: all QC metrics comfortably above their floors."""
    metrics = [
        {"name": "mapping_rate", "value": round(0.90 + 0.01 * (i % 5), 4), "floor": 0.70, "direction": "min"},
        {"name": "rin", "value": round(8.0 + 0.1 * (i % 5), 2), "floor": 6.0, "direction": "min"},
        {"name": "duplication_rate", "value": round(0.20 + 0.01 * (i % 5), 4), "floor": 0.60, "direction": "max"},
    ]
    return _qc_contract(metrics)


def qc_positive(i: int) -> Dict[str, Any]:
    """Positive (corrupt-a-QC-threshold): one QC metric falls below its floor."""
    bad = i % 3
    metrics = [
        {"name": "mapping_rate", "value": round(0.40 + 0.03 * (i % 5), 4) if bad == 0 else 0.92,
         "floor": 0.70, "direction": "min"},
        {"name": "rin", "value": round(3.0 + 0.2 * (i % 5), 2) if bad == 1 else 8.2,
         "floor": 6.0, "direction": "min"},
        {"name": "duplication_rate", "value": round(0.80 + 0.02 * (i % 5), 4) if bad == 2 else 0.25,
         "floor": 0.60, "direction": "max"},
    ]
    return _qc_contract(metrics)


# ─────────────────────────────────────────────────────────────────────────────
# 5. output.presence  (output.presence_floor — stub WS2)
# ─────────────────────────────────────────────────────────────────────────────

def _output_contract(files: List[Dict[str, Any]]) -> Dict[str, Any]:
    # A real DESeq2 run declares its primary outputs in the design block; the real
    # output.presence critic reads design.expected_outputs (filenames) and flags any
    # that the manifest does not contain.
    return {
        "design": {
            "workflow": "differential_expression_deseq2",
            "workflow_domain": "rnaseq",
            "design": {"formula": "~condition", "covariates": ["condition"],
                       "expected_outputs": ["deseq2_results.csv", "dds_object.rds"],
                       "group_sizes": {}},
            "inputs": {"counts": "counts.tsv"},
            "parameters": {},
        },
        "manifest": _manifest(files, "differential_expression_deseq2", "rnaseq"),
        "inline_artifacts": {"expected_outputs.json": {"expected_roles": ["table", "model"]}},
    }


def output_clean(i: int) -> Dict[str, Any]:
    """Negative: the expected primary outputs (table + model) are present."""
    return _output_contract([
        _file("expected_outputs.json", "metadata"),
        _file("deseq2_results.csv", "table"),
        _file("dds_object.rds", "model"),
        _file("ma_plot.png", "figure"),
    ])


def output_positive(i: int) -> Dict[str, Any]:
    """Positive (drop-the-result): run succeeded but the primary result table (and/or
    model) is missing from the manifest."""
    files = [_file("expected_outputs.json", "metadata"), _file("run.log", "metadata")]
    if i % 2 == 0:
        files.append(_file("dds_object.rds", "model"))   # table missing
    else:
        files.append(_file("deseq2_results.csv", "table"))  # model missing
    return _output_contract(files)


# ─────────────────────────────────────────────────────────────────────────────
# Dispatch tables
# ─────────────────────────────────────────────────────────────────────────────

_GENERATORS: Dict[str, Dict[str, Any]] = {
    "design.confounding": {
        "positive": confounding_positive, "negative": confounding_clean,
        "hard_negative": confounding_hard_negative},
    "design.batch_imbalance": {
        "positive": batch_positive, "negative": batch_clean,
        "hard_negative": batch_hard_negative},
    "power.epv": {
        "positive": epv_positive, "negative": epv_clean,
        "hard_negative": epv_hard_negative},
    "qc.threshold": {
        "positive": qc_positive, "negative": qc_clean},
    "output.presence": {
        "positive": output_positive, "negative": output_clean},
}


def _ground_truth(label: str) -> Dict[str, Any]:
    """Ground-truth verdict for an item label.

    positive       -> target critic SHOULD fire (true positive opportunity)
    negative       -> clean; firing is a false alarm
    hard_negative  -> looks flawed but valid; firing is a false alarm AND, if a non-FLAG
                      remediation is proposed, a harmful remediation
    """
    if label == "positive":
        return {"should_fire": True, "harmful_if_fires": False}
    if label == "negative":
        return {"should_fire": False, "harmful_if_fires": False}
    if label == "hard_negative":
        return {"should_fire": False, "harmful_if_fires": True}
    raise ValueError(label)


def generate_items(n_per_class: int = 20) -> List[Dict[str, Any]]:
    """Produce the full labeled set: for every archetype, ``n_per_class`` positives,
    negatives, and (where defined) hard negatives, each a self-contained data.jsonl
    record carrying its contract + ground-truth label."""
    items: List[Dict[str, Any]] = []
    for arch_name, spec in ARCHETYPES.items():
        gens = _GENERATORS[arch_name]
        for label in ("positive", "negative", "hard_negative"):
            gen = gens.get(label)
            if gen is None:
                continue
            for i in range(n_per_class):
                contract = gen(i)
                items.append({
                    "id": f"{arch_name}|{label}|{i:03d}",
                    "archetype": arch_name,
                    "label": label,
                    "target_critic": spec.target_critic,
                    "expected_code": spec.expected_code,
                    "clinical": spec.clinical,
                    "governance": spec.governance,
                    "ground_truth": _ground_truth(label),
                    "contract": contract,
                })
    return items
