#!/usr/bin/env python3
"""Exercise real BioMate services, with optional live dev code-runner probes.

No service mocks, model calls, Batch jobs, R installation or production edits.
Synthetic inputs test software contracts, not biological efficacy. Each check
records its expected and observed result; blocked layers never become passes.
"""
import argparse
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import platform
import sys
import tempfile
import time
import traceback
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend/lib"))
FIXTURES = ROOT / "docs/qa/sysucc-usecases"
REPORT = {"scope": "real local BioMate services and optional live dev execution; not chat/UI E2E",
          "fixture_kind": "synthetic software fixtures, not experimental evidence",
          "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
          "python": platform.python_version(), "checks": [], "observations": {}, "blocked": []}


def check(name, case, expected, actual, passed):
    REPORT["checks"].append({"name": name, "case": case, "expected": expected,
                             "actual": actual, "status": "passed" if bool(passed) else "failed"})


def run(name, fn):
    started = time.monotonic()
    try:
        fn()
    except Exception as exc:
        REPORT["checks"].append({"name": name, "case": name, "status": "error",
                                 "error": str(exc), "traceback": traceback.format_exc()})
    REPORT.setdefault("durations_s", {})[name] = round(time.monotonic() - started, 3)


def write_csv(path, rows):
    # Test-generated variations are isolated to a TemporaryDirectory.
    with path.open("w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    return str(path)


def assay_row(**overrides):
    row = dict(compound_id="A", smiles="CCO", assay_type="IC50", value="10",
               unit="nM", assay_date="2026-10-01", operator="=")
    row.update(overrides)
    return row


def comparison_and_recovery(work):
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    from galaxy.ai.drug_discovery.assay_schema import AssayCSVValidator
    svc = AssayIngestionService(str(work / "comparison.db"))
    first = svc.ingest("qa", str(FIXTURES / "assays_initial.csv"))
    second = svc.ingest("qa", str(FIXTURES / "assays_safety.csv"))
    REPORT["observations"]["two_file_comparison"] = {"initial": first, "with_safety": second}
    observed = svc.get_campaign_results("qa")
    potency = {r["compound_id"]: r["value_uM"] for r in observed if r["assay_type"] == "IC50"}
    check("normalization", "file_comparison", {"A": .001, "B": .01, "C": .1}, potency,
          potency == {"A": .001, "B": .01, "C": .1})
    check("two_files_change_decision", "file_comparison", "A initially; B after measured safety",
          [first["updated_ranks"][0]["compound_id"], second["updated_ranks"][0]["compound_id"]],
          first["updated_ranks"][0]["compound_id"] == "A" and second["updated_ranks"][0]["compound_id"] == "B")
    check("compound_identity_and_persistence", "file_comparison", "six rows; exact A/B/C IDs after reload",
          {"rows": len(observed), "ids": sorted(set(r["compound_id"] for r in observed))},
          len(observed) == 6 and {r["compound_id"] for r in observed} == {"A", "B", "C"}
          and AssayIngestionService(svc.db_path).get_ranked_compounds("qa") == svc.get_ranked_compounds("qa"))
    check("campaign_isolation", "file_comparison", [], svc.get_campaign_results("other"),
          not svc.get_campaign_results("other"))

    missing = svc.ingest("qa", write_csv(work / "incomplete.csv", [assay_row(compound_id="D", smiles="CCCl", value=".1")]))
    top = missing["updated_ranks"][0]
    check("incomplete_safety_not_unqualified_best", "file_comparison",
          "D must not become an unqualified best candidate with no safety measurement",
          {"top": top, "warning_fields": {k: v for k, v in missing.items() if k not in ("updated_ranks",)}},
          top["compound_id"] != "D" or bool(missing.get("warnings")))

    validator = AssayCSVValidator()
    for name, row in [
        ("unsupported_unit", assay_row(unit="mg/mL")),
        ("nonfinite", assay_row(value="NaN")),
        ("negative_potency", assay_row(value="-10")),
        ("negative_Kd", assay_row(value="-10", assay_type="Kd")),
        ("bad_date", assay_row(assay_date="2026-99-01")),
    ]:
        valid, errors = validator.validate(write_csv(work / (name + ".csv"), [row]))
        check(name, "failure_recovery", "reject row with an explanatory error",
              {"valid_rows": valid, "errors": errors}, not valid and bool(errors))
    bad = svc.ingest("recover", write_csv(work / "bad.csv", [assay_row(unit="mg/mL")]))
    fixed = svc.ingest("recover", write_csv(work / "fixed.csv", [assay_row()]))
    check("correct_and_resume", "failure_recovery", "bad row not persisted; corrected row ingested once",
          {"bad": bad, "fixed": fixed}, bad["ingested"] == 0 and bool(bad["errors"])
          and fixed["ingested"] == 1 and len(svc.get_campaign_results("recover")) == 1)
    conflict = svc.ingest("conflict", write_csv(work / "conflict.csv", [assay_row(), assay_row(smiles="c1ccccc1")]))
    check("conflicting_structure_identity", "failure_recovery", "reject or flag one compound ID mapped to distinct structures",
          conflict, bool(conflict.get("errors") or conflict.get("warnings")))


def learning(work):
    import numpy as np
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    from galaxy.ai.drug_discovery.bayesian_optimizer import BayesianOptimizer, CampaignDataset, _RDKIT_AVAILABLE
    from galaxy.ai.drug_discovery.auto_retrain import save_virtual_library, refit_and_propose, list_auto_proposals
    check("real_chemical_features", "experimental_learning", "RDKit available, no random-vector fallback",
          _RDKIT_AVAILABLE, _RDKIT_AVAILABLE)
    db = str(work / "learning.db")
    svc = AssayIngestionService(db)
    svc.ingest("qa-learn", str(FIXTURES / "assays_initial.csv"))
    library = ["CCCC", "CCCO", "CCCN", "CCCl"]
    save_virtual_library(db, "qa-learn", library, n_propose=2)
    before = refit_and_propose(db, "qa-learn", triggered_by="manual")
    svc.ingest("qa-learn", str(FIXTURES / "assays_safety.csv"))
    after = refit_and_propose(db, "qa-learn", triggered_by="manual")
    REPORT["observations"]["campaign_refit"] = {"before": vars(before) if before else None,
                                                "after": vars(after) if after else None}
    check("campaign_proposals_created", "experimental_learning", "two nonempty persisted proposals",
          len(list_auto_proposals(db, "qa-learn")), before is not None and after is not None
          and len(list_auto_proposals(db, "qa-learn")) == 2 and bool(after.proposed_smiles))
    if before and after:
        values = after.scores.get("composite_score", [])
        prior_values = before.scores.get("composite_score", [])
        check("campaign_uses_measured_labels", "experimental_learning",
              "predictions respond to this changed-label fixture, rather than constant fallback labels",
              {"observed_ranks": svc.get_ranked_compounds("qa-learn"), "before_scores": prior_values, "after_scores": values},
              bool(values) and len(values) == len(prior_values) and not np.allclose(values, prior_values))
        check("campaign_round_identity", "experimental_learning", "round increments after refit",
              [before.round_number, after.round_number], after.round_number == before.round_number + 1)

    # Test actual GP behavior separately from the campaign adapter; no injected optimizer.
    model = BayesianOptimizer("qa-direct", str(work / "direct.db"), n_initial=3)
    train_smi = ["CCO", "CCN", "CCC"]
    features = model._featurise(train_smi)
    holdout_smi = ["CCCC", "CCCO"]
    holdout_hash = hashlib.sha256(json.dumps(holdout_smi).encode()).hexdigest()
    predictions = []
    # Different normalized means avoid incorrectly failing valid GP reversion to
    # a shared prior mean for distant held-out structures.
    for labels in [[0., .3, 1.], [1., .9, 0.]]:
        model.fit(CampaignDataset(["A", "B", "C"], train_smi, features,
                  {"potency": np.array(labels)}, {"potency": "maximize"}))
        predictions.append(model._gp_models["potency"].predict(model._featurise(holdout_smi)).tolist())
    check("direct_gp_responds_to_labels", "experimental_learning", "different predictions on unchanged unseen SMILES",
          predictions, not np.allclose(predictions[0], predictions[1])
          and hashlib.sha256(json.dumps(holdout_smi).encode()).hexdigest() == holdout_hash)
    REPORT["observations"]["holdout_scope"] = "synthetic feature sensitivity only; no biological accuracy improvement claim"

    from galaxy.ai.ml_training.config import TrainingConfig, DatasetSpec
    from galaxy.ai.ml_training.chemprop_trainer import TrainingResult
    from galaxy.ai.ml_training.training_job import _evaluate_gate
    cfg = TrainingConfig(name="qa", campaign_id="qa", dataset=DatasetSpec(name="fixture"), metric="auc", gate_threshold=.7)
    for name, metrics, expected_pass in [
        ("missing_metric_gate", {}, False), ("infinite_metric_gate", {"val_auc": float("inf")}, False),
        ("valid_metric_gate", {"val_auc": .8}, True), ("poor_metric_gate", {"val_auc": .6}, False),
    ]:
        result = TrainingResult(model_type="sklearn_gbr", artifact_dir=str(work), metrics=metrics,
                                n_train=3, n_val=1, n_test=2, framework_version="test-data-only")
        gate = _evaluate_gate(cfg, result)
        check(name, "experimental_learning", {"passed": expected_pass},
              {"passed": gate.passed, "value": str(gate.value)}, gate.passed == expected_pass)


def evidence_and_pk(work):
    from galaxy.ai.drug_discovery.wetlab_report_ingester import WetLabReportIngester
    from galaxy.ai.local_knowledge_query import query_knowledge
    ingester = WetLabReportIngester()
    result = ingester.ingest_text((FIXTURES / "study_report.txt").read_text(), source_reference="SYNTHETIC:QA-RAT-001")
    REPORT["observations"]["study_extraction"] = result.to_dict()
    check("extracted_half_life", "evidence_package", 8, result.t_half_h.value if result.t_half_h else None,
          result.t_half_h is not None and result.t_half_h.value == 8)
    check("herg_unit_conversion", "evidence_package", 5, result.herg_ic50_uM_measured.value if result.herg_ic50_uM_measured else None,
          result.herg_ic50_uM_measured is not None and result.herg_ic50_uM_measured.value == 5)
    check("source_reference", "evidence_package", "SYNTHETIC:QA-RAT-001",
          result.t_half_h.reference if result.t_half_h else None,
          result.t_half_h is not None and result.t_half_h.reference == "SYNTHETIC:QA-RAT-001")
    check("study_species_fidelity", "evidence_package", "rat, not default human",
          result.t_half_h.species if result.t_half_h else None,
          result.t_half_h is not None and result.t_half_h.species == "rat")
    check("cmax_auc_not_dropped", "evidence_package", {"cmax": 250, "auc_inf": 1500},
          {"cmax": result.cmax_ngml.value if result.cmax_ngml else None,
           "auc_inf": result.auc_inf_ngmlh.value if result.auc_inf_ngmlh else None},
          result.cmax_ngml is not None and result.cmax_ngml.value == 250
          and result.auc_inf_ngmlh is not None and result.auc_inf_ngmlh.value == 1500)
    predicted = ingester.ingest_text("Computational prediction only: terminal half-life = 8 h. No measurements were collected.",
                                    source_reference="SYNTHETIC:PREDICTED-ONLY")
    check("predicted_not_relabelled_measured", "evidence_package", "no measured half-life",
          predicted.to_dict(), predicted.t_half_h is None or predicted.t_half_h.source != "measured_wetlab")
    unknown = ingester.ingest_structured({"t_half_h": 8}, source_reference="SYNTHETIC:UNKNOWN-GLP")
    check("unknown_glp_not_certified", "evidence_package", "no affirmative GLP claim without evidence",
          unknown.glp_certified, unknown.glp_certified is not True)

    query = query_knowledge(ROOT / "backend/database/galaxy_ai_tools.db", "PKNCA noncompartmental", limit=5)
    REPORT["observations"]["pk_method_retrieval"] = query
    check("pk_method_retrieval", "pk_analysis", "PKNCA/NCA workflow in top five, explicitly not execution-verified",
          {"names": [w["name"] for w in query["workflows"]], "execution_verified": query.get("execution_verified")},
          any("pknca" in (w["name"] + w.get("filename", "")).lower() for w in query["workflows"])
          and query.get("execution_verified") is False)
    REPORT["blocked"].append({"case": "pk_analysis", "layer": "indexed PKNCA workflow execution",
                               "reason": "not launched: authenticated project/dataset workflow journey unavailable; local Python is not a substitute for indexed R execution"})


def live_probe(base):
    if base != "https://dev-public.biomate.ai":
        raise ValueError("Only the named dev server is allowed")
    for path in ["/api/health", "/api/auth/me"]:
        with urllib.request.urlopen(base + path, timeout=25) as response:
            REPORT["observations"]["live" + path] = {"status": response.status, "body": json.load(response)}
    def execute(name, language, code):
        request = urllib.request.Request(base + "/api/code/run", data=json.dumps({"language": language, "code": code,
                                         "timeout_seconds": 20}).encode(), headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                body = json.load(response)
        except urllib.error.HTTPError as exc:
            body = {"http_status": exc.code, "body": exc.read().decode(errors="replace")}
        REPORT["observations"][name] = body
        return body

    # File contents are inline fixtures, NOT uploaded/staged dataset references.
    # This tests BioMate sandbox computation/artifacts but not model code generation.
    code = "import json,csv,io\n"
    for name, fixture in [("potency", "assays_initial.csv"), ("safety", "assays_safety.csv")]:
        code += name + " = list(csv.DictReader(io.StringIO(" + repr((FIXTURES / fixture).read_text()) + ")))\n"
    code += """
units = {'nM': .001, 'uM': 1., 'mM': 1000.}
pot = {r['compound_id']: float(r['value'])*units[r['unit']] for r in potency}
herg = {r['compound_id']: float(r['value'])*units[r['unit']] for r in safety}
rows = [{'compound_id': cid, 'ic50_uM': value, 'herg_uM': herg.get(cid),
         'eligible': value <= .01 and herg.get(cid, -1) >= 10.} for cid,value in sorted(pot.items())]
print(json.dumps({'rows': rows, 'selected': [r['compound_id'] for r in rows if r['eligible']]}), flush=True)
with open('candidate_comparison.csv','w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
"""
    result = execute("live_comparison", "python", code)
    try:
        result_data = json.loads(result.get("stdout", ""))
    except (ValueError, TypeError):
        result_data = {}
    check("live_two_file_calculation", "file_comparison", "B alone meets IC50 <= .01 uM and hERG >= 10 uM",
          result_data, result_data.get("selected") == ["B"]
          and {r.get("compound_id"): r.get("ic50_uM") for r in result_data.get("rows", [])}
          == {"A": .001, "B": .01, "C": .1})
    check("live_comparison_artifact", "file_comparison", "nonempty candidate_comparison.csv",
          result.get("output_files"), any(f.get("name") == "candidate_comparison.csv" and f.get("size", 0) > 0
                                         for f in result.get("output_files", [])) and result.get("exit_code") == 0)
    ownership = execute("live_output_directory_diagnostic", "python", "import os,json,stat\ns=os.stat(os.getcwd())\nprint(json.dumps({'uid':os.getuid(),'gid':os.getgid(),'output_owner_uid':s.st_uid,'output_owner_gid':s.st_gid,'output_mode':oct(stat.S_IMODE(s.st_mode)),'writable':os.access(os.getcwd(),os.W_OK)}))")
    REPORT["observations"]["output_directory_diagnostic_scope"] = "read-only stat of this test sandbox only"

    # Diagnostic of the permitted R code path. Never silently substitute a local
    # Python NCA calculation for the indexed R/PKNCA workflow.
    r_code = '''
if (!requireNamespace("PKNCA", quietly=TRUE)) stop("PKNCA package unavailable in BioMate code-runner; indexed workflow still requires separate execution")
library(PKNCA)
library(jsonlite)
t <- c(0,2,4,6,8,12,16,24)
df <- data.frame(subject_id="S1", time=t, conc=2^(-t/4))
concentration <- PKNCAconc(df, conc ~ time | subject_id)
dosing <- PKNCAdose(data.frame(subject_id="S1", time=0, dose=1), dose ~ time | subject_id, route="intravascular")
result <- as.data.frame(pk.nca(PKNCAdata(concentration,dosing)))
write.csv(result,"nca_results.csv",row.names=FALSE)
cat(toJSON(result, dataframe="rows", auto_unbox=TRUE))
'''
    pk = execute("live_r_pknca", "r", r_code)
    try:
        data = json.loads(pk.get("stdout", ""))
        values = {r["PPTESTCD"]: float(r["PPORRES"]) for r in data if r.get("PPORRES") is not None}
    except (ValueError, TypeError, KeyError):
        values = {}
    expected_auc = 4 / math.log(2)
    check("live_r_pknca_numerical_result", "pk_analysis", {"half.life": 4., "aucinf.obs": expected_auc}, pk,
          pk.get("exit_code") == 0 and math.isclose(values.get("half.life", -1), 4, rel_tol=.01)
          and math.isclose(values.get("aucinf.obs", -1), expected_auc, rel_tol=.01))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--output", default="docs/qa/20261029-sysucc-usecases.json")
    args = parser.parse_args()
    REPORT["fixture_hashes"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(FIXTURES.iterdir()) if p.is_file()}
    source_paths = ["scripts/test_sysucc_usecases.py", "frontend/server/code-runner.ts",
                    "backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py",
                    "backend/lib/galaxy/ai/drug_discovery/assay_schema.py",
                    "backend/lib/galaxy/ai/drug_discovery/auto_retrain.py",
                    "backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py",
                    "backend/lib/galaxy/ai/drug_discovery/wetlab_report_ingester.py",
                    "backend/lib/galaxy/ai/ml_training/training_job.py"]
    REPORT["local_source_hashes"] = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in source_paths}
    with tempfile.TemporaryDirectory(prefix="biomate-sysucc-qa-") as directory:
        work = Path(directory)
        os.environ["BIOMATE_COMPLIANCE_DB_DIR"] = str(work / "audit")
        run("file_comparison_and_recovery", lambda: comparison_and_recovery(work))
        run("experimental_learning", lambda: learning(work))
        run("evidence_package_and_pk", lambda: evidence_and_pk(work))
        if args.live:
            run("live_dev_probe", lambda: live_probe("https://dev-public.biomate.ai"))
    REPORT["blocked"].append({"case": "all four", "layer": "authenticated chat/UI journey",
                               "reason": "E2E_FIXTURE_PASSWORD unset; saved localhost session expired. No login bypass or account reset attempted."})
    REPORT["summary"] = {state: sum(c["status"] == state for c in REPORT["checks"]) for state in ("passed", "failed", "error")}
    REPORT["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    destination = ROOT / args.output
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(REPORT, indent=2, allow_nan=False) + "\n")
    print(json.dumps({"summary": REPORT["summary"], "report": str(destination)}))
    return 1 if REPORT["summary"]["failed"] or REPORT["summary"]["error"] else 0


if __name__ == "__main__":
    sys.exit(main())
