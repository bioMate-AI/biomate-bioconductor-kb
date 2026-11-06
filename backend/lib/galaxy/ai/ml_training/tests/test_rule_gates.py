"""Unit tests for the structured rule gates (gate-before-score counterpart of the
composite reward). Dep-free: pure stdlib, no trl/torch."""
from galaxy.ai.ml_training.rule_gates import evaluate_rule_gates, GateReport


# --- G1 structured threshold on a params/metrics field --------------------
def test_g1_numeric_threshold_on_field():
    spec = [{"kind": "numeric_threshold", "field": "mw", "op": "<=", "value": 500}]
    assert evaluate_rule_gates(spec, {"params": {"mw": 480}}).passed is True
    r = evaluate_rule_gates(spec, {"params": {"mw": 620}})
    assert r.passed is False
    assert r.violations[0].locus == "mw"


def test_g1_reads_metrics_bucket_and_skips_when_absent():
    spec = [{"kind": "numeric_threshold", "field": "fdr", "op": "<", "value": 0.05}]
    assert evaluate_rule_gates(spec, {"metrics": {"fdr": 0.01}}).passed is True
    assert evaluate_rule_gates(spec, {"metrics": {"fdr": 0.2}}).passed is False
    # absent field → skipped, never a fabricated block
    skipped = evaluate_rule_gates(spec, {"metrics": {}})
    assert skipped.passed is True and skipped.violations == []


# --- G6 structured cross-field implication --------------------------------
def test_g6_implies_cross_field():
    # paired-end ⇒ two fastqs present
    spec = [{"kind": "implies", "if_fields": ["paired_end"], "then_fields": ["fastq_2"]}]
    assert evaluate_rule_gates(spec, {"params": {"paired_end": True, "fastq_2": "r2.fq"}}).passed is True
    bad = evaluate_rule_gates(spec, {"params": {"paired_end": True}})
    assert bad.passed is False and bad.violations[0].locus == "fastq_2"
    # untriggered when the antecedent isn't set
    assert evaluate_rule_gates(spec, {"params": {"paired_end": False, "fastq_2": ""}}).passed is True


# --- G7 plan-DAG ordering over the step list ------------------------------
def test_g7_order_over_steps():
    spec = [{"kind": "order", "before": "qc", "after": "align"}]
    assert evaluate_rule_gates(spec, {"steps": ["qc", "align", "quant"]}).passed is True
    bad = evaluate_rule_gates(spec, {"steps": ["align", "qc"]})
    assert bad.passed is False and bad.violations[0].kind == "order"
    # a missing step → unjudgeable, not a block
    assert evaluate_rule_gates(spec, {"steps": ["align", "quant"]}).passed is True


# --- presence/banned on a named field + severity + gate-before-score ------
def test_presence_and_banned_on_field():
    spec = [
        {"kind": "contains_all", "field": "sequence", "terms": ["RGD"]},
        {"kind": "banned", "field": "sequence", "terms": ["PAINS"]},
    ]
    assert evaluate_rule_gates(spec, {"params": {"sequence": "ACRGDxx"}}).passed is True
    r = evaluate_rule_gates(spec, {"params": {"sequence": "ACxx with PAINS"}})
    assert r.passed is False
    kinds = {v.kind for v in r.violations}
    assert kinds == {"contains_all", "banned"}


def test_advisory_does_not_block():
    spec = [{"kind": "numeric_threshold", "field": "mw", "op": "<=", "value": 500, "severity": "advisory"}]
    r = evaluate_rule_gates(spec, {"params": {"mw": 999}})
    assert r.passed is True           # advisory failure does not block
    assert len(r.violations) == 1 and r.blocking() == []


def test_empty_spec_passes():
    assert evaluate_rule_gates([], {"params": {"mw": 1}}).passed is True
    assert evaluate_rule_gates(None, {}).passed is True  # type: ignore[arg-type]


def test_report_shape():
    r = evaluate_rule_gates([{"kind": "order", "before": "a", "after": "b"}], {"steps": ["b", "a"]})
    assert isinstance(r, GateReport)
    assert r.evaluated == 1 and r.passed is False
