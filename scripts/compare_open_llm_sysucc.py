#!/usr/bin/env python3
"""Standalone open-weight LLMs vs BioMate deterministic services on the SYSUCC demo cases.

Configurations
  bare      open LLM via OpenRouter chat completions; prompt + inline file contents only.
            No tools, no code execution ("standalone open model" configuration).
  biomate   BioMate's actual local services (AssayCSVValidator / AssayIngestionService /
            WetLabReportIngester) on the same inputs. No LLM. NCA has no local Python
            BioMate service (only the R/PKNCA workflow) -> recorded as not executed.
  grounded  same open LLM given the raw inputs PLUS BioMate's computed service outputs
            (platform-ablation configuration). Only for tasks where BioMate produced output.

Scoring is programmatic and field-level against frozen reference answers. Raw responses,
token usage, provider-reported cost, fixture/source SHA256 and settings are recorded.
Fixtures are synthetic; nothing confidential is sent. No production code is modified.

  python3 scripts/compare_open_llm_sysucc.py --dry-run           # freeze + BioMate only
  python3 scripts/compare_open_llm_sysucc.py --pilot             # 1 call per model
  python3 scripts/compare_open_llm_sysucc.py                     # full run (3 repeats)
"""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile
import threading
import time
import traceback
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend/lib"))
FIXTURES = ROOT / "docs/qa/sysucc-usecases"
OUT_JSON = ROOT / "docs/qa/20261030-open-llm-comparison.json"
OUT_MD = ROOT / "docs/20261030_SYSUCC_OPEN_LLM_COMPARISON.md"
OPENROUTER = "https://openrouter.ai/api/v1"

# Leaderboard (evaluation/datasets/drugdev_export/leaderboard.py) used deepseek-v4-pro,
# qwen3.8-max, glm-5.2, kimi-k3. qwen3.8-max is no longer listed; its dated slug is used.
MODELS = {
    "DeepSeek V4-pro (0813)": "deepseek/deepseek-v4-pro-0813",
    "Qwen3.8-Max (0902)": "qwen/qwen3.8-max-0902",
    "GLM-5.2": "z-ai/glm-5.2",
    "Kimi K3": "moonshotai/kimi-k3",
}
SETTINGS = {"temperature": 0, "max_tokens": 16000, "timeout_s": 900,
            "response_format": "none (JSON requested in prompt; parsed from content)",
            "reasoning": "provider default (not overridden)"}
SOURCE_PATHS = [
    "scripts/compare_open_llm_sysucc.py", "scripts/test_sysucc_usecases.py",
    "backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py",
    "backend/lib/galaxy/ai/drug_discovery/assay_schema.py",
    "backend/lib/galaxy/ai/drug_discovery/wetlab_report_ingester.py",
    "backend/lib/galaxy/ai/drug_discovery/auto_retrain.py",
    "backend/lib/galaxy/ai/drug_discovery/study_report_ingester.py",
]
SYSTEM = ("You are a careful pharmaceutical scientist. Work only from the supplied data. "
          "Return ONLY one JSON object matching the requested schema, with no markdown fences.")
HDR = "compound_id,smiles,assay_type,value,unit,assay_date,operator\n"


def sha(text):
    return hashlib.sha256(text.encode() if isinstance(text, str) else text).hexdigest()


# ─────────────────────────── frozen inputs ───────────────────────────

POTENCY = (FIXTURES / "assays_initial.csv").read_text()
SAFETY = (FIXTURES / "assays_safety.csv").read_text()
STUDY = (FIXTURES / "study_report.txt").read_text()
ADDENDUM = HDR + "D,CCCl,IC50,0.1,nM,2026-10-03,=\n"
PREDICTED_ONLY = "Computational prediction only: terminal half-life = 8 h. No measurements were collected."
ERRORS_CSV = HDR + ("P1,CC(=O)O,IC50,25,nM,2026-10-05,=\n"
                    "P2,CCN,IC50,-5,nM,2026-10-05,=\n"
                    "P3,CCCN,IC50,0.004,mg/mL,2026-10-05,=\n"
                    "P4,CCO,IC50,40,nM,2026-10-05,=\n"
                    "P4,c1ccccc1,hERG,30,uM,2026-10-06,=\n"
                    "P5,CCCC,hERG,12,uM,2026-10-06,=\n")
CORRECTED_CSV = HDR + ("P1,CC(=O)O,IC50,25,nM,2026-10-05,=\n"
                       "P2,CCN,IC50,5,nM,2026-10-05,=\n"
                       "P3,CCCN,IC50,2,uM,2026-10-05,=\n"
                       "P4,CCO,IC50,40,nM,2026-10-05,=\n"
                       "P4,CCO,hERG,30,uM,2026-10-06,=\n"
                       "P5,CCCC,hERG,12,uM,2026-10-06,=\n")

PK_T = [0.25, 0.5, 1, 2, 4, 8, 12, 24]
PK_C = [round(2 ** (-t / 4), 6) for t in PK_T]           # mg/L, 1 mg IV bolus
PK_TABLE_MG = "time_h,conc_mg_per_L\n" + "".join(f"{t},{c:.6f}\n" for t, c in zip(PK_T, PK_C))
PK_TABLE_NG = "time_h,conc_ng_per_mL\n" + "".join(f"{t},{c * 1000:.3f}\n" for t, c in zip(PK_T, PK_C))
NCA_METHOD = ("Method (use exactly): single 1 mg IV bolus at t=0; back-extrapolate C0 by log-linear "
              "regression through the first two samples; linear-up/log-down trapezoidal rule from t=0 "
              "(including the 0->first-sample interval using C0); lambda_z by unweighted log-linear "
              "least-squares regression of the last three samples (8, 12, 24 h); AUCinf = AUClast + "
              "Clast_observed/lambda_z; CL = Dose/AUCinf; Vz = CL/lambda_z.")


def nca_reference(t, c, dose, log_down=True):
    """Independent reference calculation from the sampled table (NOT a BioMate result)."""
    tt, ll = t[-3:], [math.log(x) for x in c[-3:]]
    mt, ml = sum(tt) / 3, sum(ll) / 3
    lz = -sum((a - mt) * (b - ml) for a, b in zip(tt, ll)) / sum((a - mt) ** 2 for a in tt)
    k0 = (math.log(c[1]) - math.log(c[0])) / (t[1] - t[0])
    c0 = math.exp(math.log(c[0]) - k0 * t[0])
    ts, cs = [0.0] + list(t), [c0] + list(c)
    auc = 0.0
    for i in range(len(ts) - 1):
        dt, c1, c2 = ts[i + 1] - ts[i], cs[i], cs[i + 1]
        if log_down and c2 < c1 and c2 > 0:
            auc += (c1 - c2) * dt / math.log(c1 / c2)
        else:
            auc += (c1 + c2) * dt / 2
    aucinf = auc + c[-1] / lz
    cl = dose / aucinf
    return {"lambda_z_per_h": lz, "t_half_h": math.log(2) / lz, "c0": c0, "auc_0_24": auc,
            "auc_inf": aucinf, "auc_pct_extrap": 100 * (aucinf - auc) / aucinf, "cl_L_per_h": cl,
            "vz_L": cl / lz}


NCA_MG = nca_reference(PK_T, PK_C, 1.0)                     # mg, mg/L -> mg.h/L, L/h, L
NCA_MG_LINEAR = nca_reference(PK_T, PK_C, 1.0, log_down=False)
_ng = nca_reference(PK_T, [round(c * 1000, 3) for c in PK_C], 1.0)
NCA_NG = dict(_ng, cl_L_per_h=1e6 / _ng["auc_inf"] / 1000, vz_L=1e6 / _ng["auc_inf"] / 1000 / _ng["lambda_z_per_h"])


def block(name, text):
    return f"\n--- FILE: {name} ---\n{text.strip()}\n--- END FILE ---\n"


T1_CRITERIA = ("Compare the potency and safety files by compound_id. Normalize all concentrations to uM. "
               "Select candidates meeting BOTH: potency IC50 <= 10 nM AND hERG IC50 >= 10 uM. A compound "
               "lacking either measurement must NOT be selected; list it as incomplete instead. ")
T1_SCHEMA = ('{"normalized_uM": {"<compound_id>": {"ic50_uM": number|null, "herg_uM": number|null}}, '
             '"selected": [compound_id], "incomplete": [compound_id], "rationale": string}')
T2_SCHEMA = ('{"lambda_z_per_h": n, "t_half_h": n, "c0": n, "auc_0_24": n, "auc_inf": n, '
             '"auc_pct_extrap": n, "cl_L_per_h": n, "vz_L": n}')
T3_FIELD = '{"value": number|null, "unit": string|null, "status": "measured"|"predicted"|"not_reported"}'
T3_SCHEMA = ('{"species": string, "t_half": F, "cmax": F, "auc_inf": F, "herg_ic50_uM": F, '
             '"fu_plasma": F, "noael_mg_kg_day": F, "ames": string|null, "chromosomal_aberration": '
             'string|null, "micronucleus": string|null, "glp_status": "GLP"|"non-GLP"|"not stated"}'
             ).replace("F", T3_FIELD)
T4_SCHEMA = ('{"issues": [{"row": int (CSV line number, header = line 1), "compound_id": string, '
             '"type": "negative_value"|"unit_problem"|"identity_conflict"|"other", "description": string}], '
             '"rows_safe_to_ingest": [int]}')

TASKS = {
    "T1a_two_file_selection": dict(
        case="file_comparison", grounded=True,
        prompt=T1_CRITERIA + "Schema: " + T1_SCHEMA + block("potency.csv", POTENCY) + block("safety.csv", SAFETY),
        inputs={"potency.csv": POTENCY, "safety.csv": SAFETY}),
    "T1b_incomplete_candidate": dict(
        case="file_comparison", grounded=True,
        prompt=T1_CRITERIA + "Schema: " + T1_SCHEMA + block("potency.csv", POTENCY) + block("safety.csv", SAFETY)
        + block("potency_addendum.csv", ADDENDUM),
        inputs={"potency.csv": POTENCY, "safety.csv": SAFETY, "potency_addendum.csv": ADDENDUM}),
    "T2a_nca_mg_per_L": dict(
        case="pk_analysis", grounded=False,
        prompt=("Perform non-compartmental analysis of this single-subject IV concentration-time table. "
                + NCA_METHOD + " Units: lambda_z 1/h, t_half h, c0 mg/L, AUC mg*h/L, AUC%extrap percent, "
                "CL L/h, Vz L. Schema: " + T2_SCHEMA + block("pk.csv", PK_TABLE_MG)),
        inputs={"pk.csv": PK_TABLE_MG}),
    "T2b_nca_unit_trap_ng_per_mL": dict(
        case="pk_analysis", grounded=False,
        prompt=("Perform non-compartmental analysis of this single-subject IV concentration-time table. "
                + NCA_METHOD + " Concentrations are in ng/mL; dose is 1 mg. Report: lambda_z 1/h, t_half h, "
                "c0 ng/mL, AUC ng*h/mL, AUC%extrap percent, CL in L/h, Vz in L. Schema: " + T2_SCHEMA
                + block("pk.csv", PK_TABLE_NG)),
        inputs={"pk.csv": PK_TABLE_NG}),
    "T3a_report_extraction": dict(
        case="evidence_package", grounded=True,
        prompt=("Extract the PK and safety findings from this study report, preserving values, units and "
                "species. Mark each value measured, predicted or not_reported according to the text. hERG must "
                "be reported in uM and fraction unbound as a fraction (0-1). Do not infer a GLP status the "
                "text does not establish. Schema: " + T3_SCHEMA + block("study_report.txt", STUDY)),
        inputs={"study_report.txt": STUDY}),
    "T3b_predicted_not_measured": dict(
        case="evidence_package", grounded=True,
        prompt=("Extract the PK findings from this text for a measured-evidence package. Label each value "
                "measured or predicted according to the text. Schema: {\"t_half\": " + T3_FIELD
                + ", \"measured_values_present\": boolean}" + block("note.txt", PREDICTED_ONLY)),
        inputs={"note.txt": PREDICTED_ONLY}),
    "T4_planted_data_errors": dict(
        case="failure_recovery", grounded=True,
        prompt=("Quality-check this assay table before it is ingested into a campaign database. Report every "
                "row-level scientific data problem (physically impossible values, unit problems, compound "
                "identity inconsistencies, ...) and list the CSV line numbers that are safe to ingest unchanged. "
                "Do not report problems that are not there. Schema: " + T4_SCHEMA + block("assays.csv", ERRORS_CSV)),
        inputs={"assays.csv": ERRORS_CSV}),
    "T5_corrected_resubmission": dict(
        case="failure_recovery", grounded=True,
        prompt=("The lab corrected the previous assay table (P2 IC50 is 5 nM, P3 IC50 is 2 uM, P4 structure "
                "confirmed as CCO). Normalize all values to uM and select compounds with IC50 <= 50 nM AND "
                "hERG IC50 >= 10 uM; compounds lacking either measurement must not be selected and are listed "
                "as incomplete. Schema: " + T1_SCHEMA + block("assays_corrected.csv", CORRECTED_CSV)),
        inputs={"assays_corrected.csv": CORRECTED_CSV}),
}

REFS = {
    "T1a_two_file_selection": {"normalized_uM": {"A": [.001, 1], "B": [.01, 50], "C": [.1, 25]},
                               "selected": ["B"], "incomplete": []},
    "T1b_incomplete_candidate": {"normalized_uM": {"A": [.001, 1], "B": [.01, 50], "C": [.1, 25], "D": [.0001, None]},
                                 "selected": ["B"], "incomplete": ["D"]},
    "T2a_nca_mg_per_L": NCA_MG,
    "T2b_nca_unit_trap_ng_per_mL": NCA_NG,
    "T3a_report_extraction": {"species": "rat", "t_half": 8, "cmax": 250, "auc_inf": 1500, "herg_ic50_uM": 5,
                              "fu_plasma": .035, "noael_mg_kg_day": 25, "ames": "negative",
                              "chromosomal_aberration": "negative", "micronucleus": "negative",
                              "glp_status": "not stated / non-GLP (never GLP)"},
    "T3b_predicted_not_measured": {"t_half": {"value": 8, "status": "predicted"}, "measured_values_present": False},
    "T4_planted_data_errors": {"negative_value": ("P2", 3), "unit_problem": ("P3", 4),
                               "identity_conflict": ("P4", (5, 6)), "clean_rows": {2: "P1", 7: "P5"},
                               "rows_safe_to_ingest": [2, 7]},
    "T5_corrected_resubmission": {"normalized_uM": {"P1": [.025, None], "P2": [.005, None], "P3": [2, None],
                                                    "P4": [.04, 30], "P5": [None, 12]},
                                  "selected": ["P4"], "incomplete": ["P1", "P2", "P3", "P5"]},
}
NCA_TOL = 0.02
CONC_TOL = 0.001


# ─────────────────────────── scoring ───────────────────────────

def num(v):
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v) if math.isfinite(v) else None
    if isinstance(v, dict):
        return num(v.get("value"))
    m = re.search(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", str(v))
    return float(m.group()) if m else None


def close(v, ref, tol):
    x = num(v)
    if ref is None:
        return v is None or (isinstance(v, str) and v.strip().lower() in ("", "null", "none", "n/a", "missing"))
    return x is not None and math.isclose(x, ref, rel_tol=tol)


def ids(v):
    return sorted(str(x).strip() for x in (v or []) if str(x).strip()) if isinstance(v, list) else None


def score_selection(task, out):
    ref, f = REFS[task], {}
    norm = (out or {}).get("normalized_uM") or {}
    for cid, (ic50, herg) in ref["normalized_uM"].items():
        row = norm.get(cid) or {}
        f[f"{cid}.ic50_uM"] = close(row.get("ic50_uM"), ic50, CONC_TOL)
        f[f"{cid}.herg_uM"] = close(row.get("herg_uM"), herg, CONC_TOL)
    f["selected_exact"] = ids((out or {}).get("selected")) == ref["selected"]
    if ref["incomplete"]:
        f["incomplete_flagged"] = set(ref["incomplete"]) <= set(ids((out or {}).get("incomplete")) or [])
    return f


def score_nca(task, out):
    ref = REFS[task]
    return {k: close((out or {}).get(k), ref[k], NCA_TOL) for k in
            ["lambda_z_per_h", "t_half_h", "c0", "auc_0_24", "auc_inf", "cl_L_per_h", "vz_L"]}


def _status(field):
    return str((field or {}).get("status", "")).lower() if isinstance(field, dict) else ""


def glp_ok(v):
    if v is True:
        return False
    s = str(v).strip().lower()
    if s in ("", "none", "null", "false", "unknown"):
        return True
    return bool(re.search(r"not|non|no\b|unknown|n/a", s))


def score_report(task, out):
    o, f = out or {}, {}
    if task == "T3b_predicted_not_measured":
        f["t_half_labelled_predicted"] = "predict" in _status(o.get("t_half"))
        f["no_measured_values_claimed"] = o.get("measured_values_present") is False
        return f
    ref = REFS[task]
    f["species_rat"] = "rat" in str(o.get("species", "")).lower()
    for k in ["t_half", "cmax", "auc_inf", "herg_ic50_uM", "fu_plasma", "noael_mg_kg_day"]:
        f[k] = close(o.get(k), ref[k], 0.01)
    for k in ["t_half", "cmax", "auc_inf", "herg_ic50_uM"]:
        f[k + ".measured"] = _status(o.get(k)) == "measured"
    for k in ["ames", "chromosomal_aberration", "micronucleus"]:
        f[k] = str(o.get(k, "")).lower().startswith("neg")
    f["glp_not_asserted"] = glp_ok(o.get("glp_status"))
    return f


def _issue_hits(issue, kind):
    text = (str(issue.get("type", "")) + " " + str(issue.get("description", ""))).lower()
    pats = {"negative_value": r"negative|impossible|< ?0|below zero|must be > ?0|must be positive|non-?positive|got -",
            "unit_problem": r"unit|mg/ml|mass concentration|molar",
            "identity_conflict": r"identity|smiles|structure|conflict|inconsisten|duplicate"}
    return re.search(pats[kind], text) is not None


def score_errors(task, out):
    ref, o, f = REFS[task], out or {}, {}
    issues = [i for i in (o.get("issues") or []) if isinstance(i, dict)]

    def about(i, cid, rows):
        rows = rows if isinstance(rows, tuple) else (rows,)
        return str(i.get("compound_id", "")).strip() == cid or num(i.get("row")) in [float(r) for r in rows]
    for kind in ["negative_value", "unit_problem", "identity_conflict"]:
        cid, rows = ref[kind]
        f["detected." + kind] = any(about(i, cid, rows) and _issue_hits(i, kind) for i in issues)
    # A note that a clean row's compound lacks another assay is a coverage note, not a claim that the row is wrong.
    coverage = re.compile(r"incomplete|missing (safety|potency|measurement)|not (yet )?(fully )?evaluated|"
                          r"lacks? (an? )?(hERG|IC50|potency|safety)", re.I)
    fps = [i for i in issues if any(about(i, cid, r) for r, cid in ref["clean_rows"].items())
           and not coverage.search(str(i.get("type", "")) + " " + str(i.get("description", "")))]
    f["no_false_positive_on_clean_rows"] = not fps
    safe = o.get("rows_safe_to_ingest")
    f["rows_safe_to_ingest_exact"] = isinstance(safe, list) and sorted(int(num(x) or -1) for x in safe) == ref["rows_safe_to_ingest"]
    return f


SCORERS = {"T1a_two_file_selection": score_selection, "T1b_incomplete_candidate": score_selection,
           "T5_corrected_resubmission": score_selection, "T2a_nca_mg_per_L": score_nca,
           "T2b_nca_unit_trap_ng_per_mL": score_nca, "T3a_report_extraction": score_report,
           "T3b_predicted_not_measured": score_report, "T4_planted_data_errors": score_errors}


def score(task, out):
    fields = SCORERS[task](task, out)
    return {"fields": fields, "passed": sum(fields.values()), "total": len(fields),
            "fraction": round(sum(fields.values()) / len(fields), 4), "fully_correct": all(fields.values())}


# ─────────────────────────── BioMate deterministic path ───────────────────────────

def _flag_mentions(obj, cid):
    """Look for an incompleteness/warning signal naming cid anywhere a fixed service could put it."""
    hits = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if re.search(r"warn|incomplete|missing|coverage|flag", str(k), re.I) and v:
                if re.search(rf"\b{re.escape(cid)}\b", json.dumps(v, default=str)):
                    hits.append(k)
    return hits


def biomate_selection(task, work):
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    svc = AssayIngestionService(str(work / f"{task}.db"))
    summaries = []
    for name, text in TASKS[task]["inputs"].items():
        p = work / f"{task}_{name}"
        p.write_text(text)
        summaries.append({"file": name, "result": svc.ingest("cmp", str(p))})
    rows = svc.get_campaign_results("cmp")
    ranks = svc.get_ranked_compounds("cmp")
    last = summaries[-1]["result"]
    norm = {}
    for r in rows:
        key = "herg_uM" if r["assay_type"] == "hERG" else "ic50_uM" if r["assay_type"] == "IC50" else None
        if key:
            norm.setdefault(r["compound_id"], {"ic50_uM": None, "herg_uM": None})[key] = r["value_uM"]
    rank_rows = last.get("updated_ranks") or ranks
    eligible_keys = [k for k in (rank_rows[0] if rank_rows else {}) if re.search(r"eligib|qualif|selected", k)]
    if eligible_keys:
        selected = [r["compound_id"] for r in rank_rows if r.get(eligible_keys[0])]
        rule = f"service field '{eligible_keys[0]}'"
    else:
        selected = [rank_rows[0]["compound_id"]] if rank_rows else []
        rule = "no criteria filter in service: top combined_score rank treated as its recommendation"
    incomplete = sorted({cid for cid in norm if any(_flag_mentions(s["result"], cid) for s in summaries)
                         or any(_flag_mentions(r, cid) for r in rank_rows if r.get("compound_id") == cid)})
    out = {"normalized_uM": norm, "selected": selected, "incomplete": incomplete}
    return out, {"selection_rule": rule, "ingest_summaries": summaries, "ranked": ranks}


def biomate_report(task, work):
    from galaxy.ai.drug_discovery.wetlab_report_ingester import WetLabReportIngester
    ing = WetLabReportIngester()
    text = STUDY if task == "T3a_report_extraction" else PREDICTED_ONLY
    res = ing.ingest_text(text, source_reference="SYNTHETIC:" + task)
    d = res.to_dict()

    def mv(key):
        v = d.get(key)
        if not v:
            return {"value": None, "unit": None, "status": "not_reported"}
        src = str(v.get("source", "")).lower()
        status = "predicted" if "predict" in src else "measured" if "measured" in src else src
        return {"value": v.get("value"), "unit": v.get("unit"), "status": status}
    if task == "T3b_predicted_not_measured":
        measured = [k for k, v in d.items() if isinstance(v, dict) and "measured" in str(v.get("source", "")).lower()]
        t_half = mv("t_half_h")
        predicted = (d.get("predicted_values") or {}).get("t_half_h")
        if t_half["value"] is None and isinstance(predicted, dict):
            t_half = {"value": predicted.get("value"), "unit": predicted.get("unit"), "status": "predicted"}
        return {"t_half": t_half, "measured_values_present": bool(measured)}, {
            "service_output": d, "mapping": "measured fields, else predicted_values.t_half_h -> status 'predicted'"}
    species = (d.get("t_half_h") or {}).get("species")
    glp = d.get("glp_certified")
    out = {"species": species, "t_half": mv("t_half_h"), "cmax": mv("cmax_ngml"), "auc_inf": mv("auc_inf_ngmlh"),
           "herg_ic50_uM": mv("herg_ic50_uM_measured"), "fu_plasma": mv("fu_plasma"),
           "noael_mg_kg_day": mv("noael_mg_kg_day"), "ames": d.get("ames_in_vitro"),
           "chromosomal_aberration": d.get("chromosomal_aberration"), "micronucleus": d.get("micronucleus"),
           "glp_status": "GLP" if glp is True else glp}
    return out, {"service_output": d, "mapping": "WetLabStudyData fields -> task schema; glp_certified True -> 'GLP'"}


def biomate_errors(task, work):
    from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
    from galaxy.ai.drug_discovery.assay_schema import AssayCSVValidator
    p = work / "errors.csv"
    p.write_text(ERRORS_CSV)
    valid, v_errors = AssayCSVValidator().validate(str(p))
    svc = AssayIngestionService(str(work / "errors.db"))
    ing = svc.ingest("qc", str(p))
    messages = [str(m) for m in (ing.get("errors") or [])]
    for k, v in ing.items():
        if re.search(r"warn|conflict|flag", k, re.I) and v:
            messages += [json.dumps(x, default=str) for x in (v if isinstance(v, list) else [v])]
    lines = ERRORS_CSV.strip().splitlines()[1:]
    issues = []
    for msg in messages:
        rows = [int(x) for x in re.findall(r"[Rr]ow\s*(\d+)", msg)]
        cids = [c for c in ["P1", "P2", "P3", "P4", "P5"] if re.search(rf"\b{c}\b", msg)]
        for r in rows or [None]:
            cid = lines[r - 2].split(",")[0] if r and 2 <= r <= len(lines) + 1 else (cids[0] if cids else "")
            issues.append({"row": r, "compound_id": cid, "type": "other", "description": msg})
    persisted = svc.get_campaign_results("qc")
    safe = sorted(i + 2 for i, line in enumerate(lines) for r in persisted
                  if line.split(",")[:3] == [r["compound_id"], r["smiles"], r["assay_type"]])
    out = {"issues": issues, "rows_safe_to_ingest": sorted(set(safe))}
    return out, {"validator_valid_rows": len(valid), "validator_errors": v_errors, "ingest": ing,
                 "persisted_rows": persisted,
                 "mapping": "error/warning messages -> issues (type matched on message text); persisted rows -> rows_safe_to_ingest"}


def run_biomate(work):
    results = {}
    for task in TASKS:
        try:
            if task.startswith("T2"):
                results[task] = {"status": "not_executed_locally", "reason": (
                    "BioMate's NCA capability is the indexed R/PKNCA Nextflow workflow "
                    "(backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/nca_pknca). "
                    "No local Python BioMate NCA service exists; R is not installed locally and no "
                    "substitute calculation is attributed to BioMate.")}
                continue
            fn = biomate_report if task.startswith("T3") else biomate_errors if task.startswith("T4") else biomate_selection
            out, evidence = fn(task, work)
            results[task] = {"status": "executed", "output": out, "evidence": evidence, "score": score(task, out)}
        except Exception as exc:
            results[task] = {"status": "error", "error": str(exc), "traceback": traceback.format_exc()}
    return results


# ─────────────────────────── OpenRouter client ───────────────────────────

def extract_json(text):
    if not text:
        return None
    t = re.sub(r"^```(?:json)?\s*|\s*```$", "", text.strip(), flags=re.S)
    try:
        return json.loads(t)
    except ValueError:
        pass
    start = t.find("{")
    while start != -1:
        depth = 0
        for i in range(start, len(t)):
            depth += {"{": 1, "}": -1}.get(t[i], 0)
            if depth == 0:
                try:
                    return json.loads(t[start:i + 1])
                except ValueError:
                    break
        start = t.find("{", start + 1)
    return None


def call_openrouter(slug, prompt, force_reasoning=False):
    key = os.environ["OPENROUTER_API_KEY"]
    body = {"model": slug, "temperature": SETTINGS["temperature"], "max_tokens": SETTINGS["max_tokens"],
            "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": prompt}],
            "usage": {"include": True}}
    if force_reasoning:
        # Some OpenRouter providers serve a slug without thinking; route only to ones honouring it.
        body["reasoning"] = {"enabled": True}
        body["provider"] = {"require_parameters": True}
    attempts = []
    for attempt in range(5):
        started = time.time()
        req = urllib.request.Request(OPENROUTER + "/chat/completions", data=json.dumps(body).encode(),
                                     headers={"Authorization": "Bearer " + key, "Content-Type": "application/json",
                                              "X-Title": "BioMate SYSUCC open-LLM comparison"})
        try:
            with urllib.request.urlopen(req, timeout=SETTINGS["timeout_s"]) as r:
                data = json.load(r)
            if "error" in data:
                raise RuntimeError(json.dumps(data["error"]))
            ch = (data.get("choices") or [{}])[0]
            msg = ch.get("message") or {}
            return {"ok": True, "content": msg.get("content") or "", "reasoning_chars": len(msg.get("reasoning") or ""),
                    "finish_reason": ch.get("finish_reason"), "native_finish_reason": ch.get("native_finish_reason"),
                    "usage": data.get("usage"), "provider": data.get("provider"), "model_returned": data.get("model"),
                    "id": data.get("id"), "latency_s": round(time.time() - started, 1), "attempts": attempts}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:2000]
            attempts.append({"http_status": exc.code, "body": detail})
            if exc.code == 402 and "in_flight_budget_exhausted" in detail:
                # OpenRouter reserves max_tokens x price per concurrent request; unbilled, retry after it settles.
                time.sleep(int(exc.headers.get("Retry-After") or 120))
                continue
            if exc.code not in (408, 429, 500, 502, 503, 504):
                break
        except Exception as exc:
            attempts.append({"error": repr(exc)[:2000]})
            if "timed out" in repr(exc).lower():
                break  # a timed-out generation may still be billed; do not pay twice
        time.sleep(5 * (attempt + 1))
    return {"ok": False, "attempts": attempts}


def grounded_prompt(task, biomate):
    b = biomate.get(task, {})
    tool = {"service_output_mapped_to_schema": b.get("output"), "service_evidence": b.get("evidence")}
    return (TASKS[task]["prompt"] + "\n\nBioMate deterministic service outputs for these same inputs "
            "(computed by BioMate's assay-ingestion / report-ingestion services; verify them against the "
            "files above before relying on them):\n" + json.dumps(tool, default=str)[:30000])


# ─────────────────────────── reporting ───────────────────────────

def agg(runs):
    ok = [r for r in runs if "score" in r]
    if not ok:
        return None
    fr = [r["score"]["fraction"] for r in ok]
    return {"n_runs": len(runs), "n_scored": len(ok), "mean_field_fraction": round(sum(fr) / len(fr), 3),
            "min": min(fr), "max": max(fr), "fully_correct": sum(r["score"]["fully_correct"] for r in ok),
            "field_passes": sum(r["score"]["passed"] for r in ok), "field_total": sum(r["score"]["total"] for r in ok)}


def write_markdown(report):
    L = []
    s = report["summary"]
    L.append("# SYSUCC demo cases: standalone open LLMs vs BioMate deterministic services\n")
    L.append(f"Run: {report['started_at']} → {report['finished_at']} (UTC). Raw data: "
             "[`docs/qa/20261030-open-llm-comparison.json`](qa/20261030-open-llm-comparison.json). "
             "Harness: [`scripts/compare_open_llm_sysucc.py`](../scripts/compare_open_llm_sysucc.py).\n")
    L.append("**Illustrative, not statistically established.** Each cell is at most 3 repeats on one "
             "synthetic fixture per task. Fixtures are synthetic software fixtures, not hospital or experimental data.\n")
    prior = OUT_MD.read_text() if OUT_MD.exists() else ""
    m = re.search(r"<!-- analyst:start -->.*?<!-- analyst:end -->", prior, re.S)
    L.append(m.group() if m else "<!-- analyst:start -->\n_Analyst interpretation not yet written for this run._\n<!-- analyst:end -->")
    L.append("\n# Generated results\n")
    L.append("## Configurations\n")
    L.append("- **bare** — open model via OpenRouter chat completions, prompt + inline file text only, "
             "no tools and **no code execution**. This is the *standalone open model* configuration; a "
             "code-enabled agent built on the same model might do better, and was not tested.")
    L.append("- **biomate** — BioMate's current local Python services on the same inputs, no LLM. "
             "These services are being fixed concurrently; results reflect the source hashes in the JSON.")
    L.append("- **grounded** — the same open model given the raw files *plus* BioMate's service outputs "
             "(platform ablation). Not run for T2 (no BioMate output). Repeats: bare "
             + str(max((len(r) for t in report["runs"].get("bare", {}).values() for r in t.values()), default=0))
             + ", grounded " + str(max((len(r) for t in report["runs"].get("grounded", {}).values() for r in t.values()), default=0))
             + " per model per task.\n")
    L.append("Models: " + ", ".join(f"`{v}`" for v in report["models"].values())
             + f". Settings: temperature {SETTINGS['temperature']}, max_tokens {SETTINGS['max_tokens']}, "
             "provider-default reasoning, JSON requested in the prompt.\n")
    L.append(f"Spend: {s['llm_calls']} LLM calls, {s['prompt_tokens']:,} prompt + {s['completion_tokens']:,} "
             f"completion tokens (incl. {s['reasoning_tokens']:,} reasoning), provider-reported cost "
             f"${s['cost_usd']:.3f}.\n")
    L.append("## Scores (mean field-level fraction; fully-correct runs / scored runs)\n")
    colspec = [(cfg, c) for cfg in ["bare", "bare_reasoning", "grounded"] for c in report["models"]
               if any(c in ms for ms in report["runs"].get(cfg, {}).values())]
    L.append("| Task | BioMate det. | " + " | ".join(f"{cfg} {c}" for cfg, c in colspec) + " |")
    L.append("|---|---|" + "---|" * len(colspec))
    for task in TASKS:
        b = report["biomate"][task]
        bcell = (f"{b['score']['fraction']:.2f} ({int(b['score']['fully_correct'])}/1)" if b.get("score")
                 else b["status"])
        cells = []
        for cfg, c in colspec:
            a = report["aggregate"].get(cfg, {}).get(task, {}).get(c)
            cells.append("—" if a is None else f"{a['mean_field_fraction']:.2f} ({a['fully_correct']}/{a['n_scored']})"
                         + ("" if a["n_scored"] == a["n_runs"] else f" [{a['n_runs'] - a['n_scored']} unscored]"))
        L.append(f"| {task} | {bcell} | " + " | ".join(cells) + " |")
    L.append("\nCells: mean field fraction (fully-correct runs / scored runs). Unparseable or truncated "
             "output (e.g. reasoning exhausted the 16k-token budget) scores 0 and is counted, not dropped.")
    L.append("\nField denominators per run: " + ", ".join(
        f"{t} = {len(SCORERS[t](t, {}))}" for t in TASKS) + ".\n")
    L.append("## Per-task verdict (rule-based)\n")
    L.append("Rule: compare BioMate deterministic field fraction with the pooled bare-model mean; "
             "difference > +0.10 = BioMate wins, < −0.10 = BioMate loses, otherwise tie. Same rule for grounded vs bare.\n")
    L.append("| Task | BioMate det. | bare pooled mean | best bare model | BioMate vs bare | DeepSeek reasoning-forced mean | grounded pooled mean | grounded vs bare |")
    L.append("|---|---|---|---|---|---|---|---|")
    for task, v in report["verdicts"].items():
        L.append(f"| {task} | {v['biomate']} | {v['bare_mean']} | {v['bare_best']} | {v['biomate_vs_bare']} | "
                 f"{v['bare_reasoning_mean']} | {v['grounded_mean']} | {v['grounded_vs_bare']} |")
    L.append("\n## Provider routing and reasoning (per run)\n")
    L.append("OpenRouter chooses a provider per request unless pinned. `prov(reasoning tokens)` per repeat:\n")
    L.append("| Config | Task | Model | runs |")
    L.append("|---|---|---|---|")
    for cfg, ts in report["runs"].items():
        for task, ms in ts.items():
            for m, rs in ms.items():
                L.append(f"| {cfg} | {task} | {m} | " + ", ".join(
                    f"{r.get('provider')}({((r.get('usage') or {}).get('completion_tokens_details') or {}).get('reasoning_tokens')}"
                    f"{'' if r.get('finish_reason') != 'length' else ', truncated'})" for r in rs) + " |")
    L.append("\n## Field failures (exact model values)\n")
    for task in TASKS:
        ex = report["failure_examples"].get(task) or []
        if ex:
            L.append(f"**{task}** — reference: `{json.dumps(REFS[task], default=str)[:300]}`\n")
            for e in ex[:14]:
                L.append(f"- {e}")
            L.append("")
    L.append("## BioMate deterministic path: failed fields\n")
    for task, b in report["biomate"].items():
        if b.get("score"):
            bad = [k for k, v in b["score"]["fields"].items() if not v]
            L.append(f"- **{task}**: {('failed ' + ', '.join(bad)) if bad else 'all fields passed'}")
        else:
            L.append(f"- **{task}**: {b['status']} — {b.get('reason') or b.get('error')}")
    L.append("\n## Caveats\n")
    L.append("- Small n (≤3 repeats × 1 fixture per task); results are illustrative and could change with "
             "different fixtures, prompts or providers. Temperature 0 was requested; OpenRouter providers "
             "may still be nondeterministic, and some reasoning models may ignore temperature.")
    L.append("- The bare LLMs had no code execution. Hand arithmetic on logs/regressions (T2) is the hardest "
             "part for them; a code-interpreter agent would likely close much of that gap.")
    L.append("- BioMate's NCA is an R/PKNCA workflow that was not executed here; BioMate has no T2 score.")
    L.append("- Provider routing matters: OpenRouter picks a provider per request, and some serve a slug without "
             "thinking. `bare_reasoning` re-runs DeepSeek with reasoning forced on (providers honouring the "
             "parameter only). A hospital's own DeepSeek deployment settings determine which behaviour it gets.")
    L.append("- 16k completion-token cap: runs that spent it all on reasoning returned no answer and score 0. "
             "A larger budget might let those models finish, at higher cost and latency.")
    L.append("- BioMate's assay service ranks compounds and has no explicit criteria filter; its top-ranked "
             "compound is scored as its recommendation (same interpretation as `scripts/test_sysucc_usecases.py`).")
    L.append("- BioMate results depend on fixes in progress to `assay_ingestion.py`, `auto_retrain.py` and the "
             "report-ingestion code; rerun the harness after those land. Source hashes are in the JSON.")
    L.append("- Prompts fully specify the NCA method and the selection criteria, so this measures execution "
             "fidelity, not method choice.")
    OUT_MD.write_text("\n".join(L) + "\n")


def build_verdicts(report):
    out = {}
    for task in TASKS:
        b = report["biomate"][task]
        bf = b["score"]["fraction"] if b.get("score") else None

        def pooled(cfg):
            runs = [r for m in report["runs"].get(cfg, {}).get(task, {}).values() for r in m if "score" in r]
            return round(sum(r["score"]["fraction"] for r in runs) / len(runs), 3) if runs else None
        bare, grd = pooled("bare"), pooled("grounded")
        aggs = report["aggregate"].get("bare", {}).get(task, {})
        best = max(((a["mean_field_fraction"], c) for c, a in aggs.items() if a), default=None)

        def cmp(x, y, label):
            if x is None or y is None:
                return "n/a"
            return f"{label} wins" if x - y > .1 else f"{label} loses" if y - x > .1 else "tie"
        out[task] = {"biomate": bf if bf is not None else b["status"], "bare_mean": bare,
                     "bare_reasoning_mean": pooled("bare_reasoning"),
                     "bare_best": f"{best[1]} {best[0]:.2f}" if best else None,
                     "biomate_vs_bare": cmp(bf, bare, "BioMate"), "grounded_mean": grd,
                     "grounded_vs_bare": cmp(grd, bare, "grounded")}
    return out


def failure_examples(report):
    ex = {}
    for cfg in ["bare", "bare_reasoning", "grounded"]:
        for task, models in report["runs"].get(cfg, {}).items():
            for label, runs in models.items():
                for i, r in enumerate(runs):
                    rt = ((r.get("usage") or {}).get("completion_tokens_details") or {}).get("reasoning_tokens")
                    tag = f"{cfg} {label} run{i + 1} [{r.get('provider')}, reasoning={rt}]"
                    if "score" not in r:
                        ex.setdefault(task, []).append(f"{tag}: unscored — {r.get('error', '')[:200]}")
                        continue
                    if r["score"].get("unparseable"):
                        ex.setdefault(task, []).append(f"{tag}: no answer — {r.get('error')}")
                        continue
                    bad = [k for k, v in r["score"]["fields"].items() if not v]
                    if bad:
                        ex.setdefault(task, []).append(
                            f"{tag}: failed {', '.join(bad)}; returned "
                            f"`{json.dumps(pick(task, r.get('parsed'), bad), default=str)[:400]}`")
    return ex


def pick(task, parsed, bad):
    if not isinstance(parsed, dict):
        return parsed
    keys = {b.split(".")[0] for b in bad}
    if task.startswith(("T1", "T5")):
        sub = {k: parsed.get(k) for k in ("selected", "incomplete")}
        sub["normalized_uM"] = {k: v for k, v in (parsed.get("normalized_uM") or {}).items() if k in keys}
        return sub
    if task.startswith("T4"):
        return {"issues": [(i.get("row"), i.get("compound_id"), i.get("type")) for i in parsed.get("issues") or []
                           if isinstance(i, dict)], "rows_safe_to_ingest": parsed.get("rows_safe_to_ingest")}
    alias = {"species_rat": "species", "glp_not_asserted": "glp_status", "t_half_labelled_predicted": "t_half",
             "no_measured_values_claimed": "measured_values_present"}
    return {alias.get(k, k): parsed.get(alias.get(k, k)) for k in keys}


# ─────────────────────────── main ───────────────────────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--configs", default="bare,grounded")
    ap.add_argument("--models", default=",".join(MODELS))
    ap.add_argument("--tasks", default=",".join(TASKS))
    ap.add_argument("--pilot", action="store_true", help="1 call per model on T2a; no files written")
    ap.add_argument("--dry-run", action="store_true", help="freeze inputs + run BioMate path only")
    ap.add_argument("--workers", type=int, default=3, help="low: OpenRouter caps in-flight reserved spend")
    ap.add_argument("--rescore", action="store_true",
                    help="no LLM calls: re-run the BioMate path, re-score stored parsed responses, rewrite outputs")
    ap.add_argument("--resume", action="store_true",
                    help="reuse completed calls from the existing JSON; only re-issue calls that failed at the HTTP layer")
    ap.add_argument("--grounded-repeats", type=int, default=1, help="kept low to bound spend")
    ap.add_argument("--reasoning-models", default="DeepSeek V4-pro (0813)",
                    help="models for the supplementary bare_reasoning config (reasoning forced on)")
    ap.add_argument("--merge", action="store_true",
                    help="keep runs of configs not re-run now from the existing JSON (e.g. add grounded to bare)")
    args = ap.parse_args()
    models = {k: MODELS[k] for k in args.models.split(",")}
    tasks = args.tasks.split(",")

    report = {
        "scope": "standalone open LLMs (no tools) vs BioMate deterministic local services vs LLM grounded on BioMate outputs",
        "fixture_kind": "synthetic software fixtures; no hospital data", "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "python": sys.version.split()[0], "models": models, "settings": SETTINGS, "system_prompt": SYSTEM,
        "fixture_hashes": {p.name: sha(p.read_bytes()) for p in sorted(FIXTURES.iterdir()) if p.is_file()},
        "local_source_hashes": {p: sha((ROOT / p).read_bytes()) for p in SOURCE_PATHS if (ROOT / p).exists()},
        "tasks": {t: {"case": v["case"], "prompt": v["prompt"], "prompt_sha256": sha(v["prompt"]),
                      "inputs_sha256": {n: sha(x) for n, x in v["inputs"].items()}, "reference": REFS[t],
                      "grounded_config": v["grounded"]} for t, v in TASKS.items()},
        "nca_reference_notes": {"method": NCA_METHOD, "tolerance_rel": NCA_TOL,
                                "analytic_auc_inf_mg_h_per_L": 4 / math.log(2),
                                "linear_trapezoid_alternative (not accepted; recorded to diagnose method drift)": NCA_MG_LINEAR},
        "tolerances": {"nca_rel": NCA_TOL, "concentration_rel": CONC_TOL, "report_values_rel": 0.01},
    }
    try:
        import subprocess
        report["git_head"] = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                                            capture_output=True, text=True).stdout.strip()
    except Exception:
        pass

    with tempfile.TemporaryDirectory(prefix="biomate-openllm-cmp-") as d:
        os.environ["BIOMATE_COMPLIANCE_DB_DIR"] = str(Path(d) / "audit")
        report["biomate"] = run_biomate(Path(d))

    if args.pilot:
        for label, slug in models.items():
            r = call_openrouter(slug, TASKS["T2a_nca_mg_per_L"]["prompt"])
            parsed = extract_json(r.get("content")) if r.get("ok") else None
            print(json.dumps({"model": slug, "ok": r.get("ok"), "finish": r.get("finish_reason"), "usage": r.get("usage"),
                              "provider": r.get("provider"), "latency": r.get("latency_s"),
                              "score": score("T2a_nca_mg_per_L", parsed) if parsed else None,
                              "attempts": r.get("attempts"), "content": (r.get("content") or "")[:300]}, indent=1))
        return 0

    jobs = []
    if not args.dry_run:
        for cfg in args.configs.split(","):
            for task in tasks:
                if cfg == "grounded" and not (TASKS[task]["grounded"] and report["biomate"][task].get("status") == "executed"):
                    continue
                for label, slug in models.items():
                    if cfg == "bare_reasoning" and label not in args.reasoning_models.split(","):
                        continue
                    for rep in range(args.grounded_repeats if cfg == "grounded" else args.repeats):
                        jobs.append((cfg, task, label, slug, rep))
    report["runs"] = {}
    if args.merge and OUT_JSON.exists():
        prior = json.loads(OUT_JSON.read_text())
        rerun = set(args.configs.split(","))
        report["runs"] = {c: v for c, v in prior.get("runs", {}).items() if c not in rerun}
        report["merged_from_prior_run"] = {"configs": sorted(report["runs"]), "prior_started_at": prior.get("started_at"),
                                           "prior_local_source_hashes": prior.get("local_source_hashes")}
    if args.rescore:
        prior = json.loads(OUT_JSON.read_text())
        jobs = []
        for cfg, ts in prior.get("runs", {}).items():
            for task, ms in ts.items():
                for label, rs in ms.items():
                    for r in rs:
                        if "score" in r:
                            r["score_before_rescore"] = r.get("score_before_rescore", r["score"])
                            r["score"] = score(task, r.get("parsed") if isinstance(r.get("parsed"), dict) else {})
                            if r.get("parsed") is None:
                                r["score"]["unparseable"] = True
        report["runs"] = prior["runs"]
        report["started_at"] = prior.get("started_at", report["started_at"])
        report["rescored"] = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                              "llm_runs_from": prior.get("started_at"),
                              "llm_run_local_source_hashes": (prior.get("rescored") or {}).get(
                                  "llm_run_local_source_hashes", prior.get("local_source_hashes"))}
        for k in ("resumed_from_prior_run", "merged_from_prior_run"):
            if k in prior:
                report[k] = prior[k]
    if args.resume and OUT_JSON.exists():
        prior = json.loads(OUT_JSON.read_text())
        kept = 0
        for cfg, ts in prior.get("runs", {}).items():
            for task, ms in ts.items():
                for label, rs in ms.items():
                    for r in rs:
                        if not str(r.get("error", "")).startswith("call failed"):
                            report["runs"].setdefault(cfg, {}).setdefault(task, {}).setdefault(label, []).append(r)
                            kept += 1
        done = {(c, t, m, r["repeat"] - 1) for c, ts in report["runs"].items() for t, ms in ts.items()
                for m, rs in ms.items() for r in rs}
        jobs = [j for j in jobs if (j[0], j[1], j[2], j[4]) not in done]
        report["resumed_from_prior_run"] = {"prior_started_at": prior.get("started_at"), "kept_calls": kept,
                                            "reissued_calls": len(jobs),
                                            "prior_local_source_hashes": prior.get("local_source_hashes")}
        report["started_at"] = prior.get("started_at", report["started_at"])
    lock = threading.Lock()

    def work(job):
        cfg, task, label, slug, rep = job
        prompt = grounded_prompt(task, report["biomate"]) if cfg == "grounded" else TASKS[task]["prompt"]
        r = call_openrouter(slug, prompt, force_reasoning=(cfg == "bare_reasoning"))
        rec = {"repeat": rep + 1, "prompt_sha256": sha(prompt), **{k: v for k, v in r.items() if k != "ok"}}
        if cfg == "grounded":
            rec["prompt"] = prompt
        if not r.get("ok"):
            rec["error"] = "call failed: " + json.dumps(r.get("attempts"))[:500]
        else:
            parsed = extract_json(r["content"])
            rec["parsed"] = parsed
            if parsed is None:
                rec["error"] = f"no parseable JSON (finish_reason={r.get('finish_reason')})"
                rec["score"] = score(task, {})          # unparseable output scores zero, still counted
                rec["score"]["unparseable"] = True
            else:
                rec["score"] = score(task, parsed)
        with lock:
            report["runs"].setdefault(cfg, {}).setdefault(task, {}).setdefault(label, []).append(rec)
            print(f"[{cfg}] {task} {label} r{rep + 1}: "
                  + (f"{rec['score']['passed']}/{rec['score']['total']}" if "score" in rec else rec.get("error", "")[:120]),
                  flush=True)
    with ThreadPoolExecutor(args.workers) as pool:
        list(pool.map(work, jobs))
    for cfg in report["runs"].values():
        for models_ in cfg.values():
            for runs in models_.values():
                runs.sort(key=lambda r: r["repeat"])

    report["aggregate"] = {cfg: {t: {m: agg(rs) for m, rs in ms.items()} for t, ms in ts.items()}
                           for cfg, ts in report["runs"].items()}
    usage = [r.get("usage") or {} for ts in report["runs"].values() for ms in ts.values() for rs in ms.values() for r in rs]
    report["summary"] = {
        "llm_calls": len(usage), "prompt_tokens": sum(u.get("prompt_tokens", 0) for u in usage),
        "completion_tokens": sum(u.get("completion_tokens", 0) for u in usage),
        "reasoning_tokens": sum((u.get("completion_tokens_details") or {}).get("reasoning_tokens", 0) or 0 for u in usage),
        "cost_usd": round(sum(u.get("cost", 0) or 0 for u in usage), 4),
        "per_model_cost_usd": {m: round(sum((r.get("usage") or {}).get("cost", 0) or 0 for ts in report["runs"].values()
                                            for rs in [ms.get(m, []) for ms in ts.values()] for r in rs), 4) for m in models},
    }
    report["verdicts"] = build_verdicts(report)
    report["failure_examples"] = failure_examples(report)
    report["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    if args.dry_run:
        print(json.dumps({t: b.get("score", b.get("status")) for t, b in report["biomate"].items()}, indent=1, default=str))
        print(json.dumps({"nca_mg": NCA_MG, "nca_ng": NCA_NG, "linear_alt": NCA_MG_LINEAR}, indent=1))
        return 0
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(report, indent=2, default=str, allow_nan=False) + "\n")
    write_markdown(report)
    print(json.dumps({"summary": report["summary"], "json": str(OUT_JSON), "md": str(OUT_MD)}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
