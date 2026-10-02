"""Execution grader for BioMate end-to-end runs — the VALID grader the hard tasks need.

An objective PASS/FAIL from what a run actually DID, not from string similarity and not from an LLM:
  L1 (metadata, default): terminal success (status completed, nextflow returncode 0 / 'succeeded')
     AND at least one NON-versions output file with size > 0.
  L2 (--deep): also fetch each result output from S3 and validate CONTENT — CSV parses with >=1 data
     row, JSON parses to a non-empty object/array. This is "the output passes a programmatic check".
  Optional per-workflow CONTRACT: required output basenames + required JSON keys (true correctness,
  not just 'something ran').

Usage:
  python execution_grader.py --runs fixtures.json              # L1 on a saved runs array
  python execution_grader.py --runs fixtures.json --deep       # + S3 content validation
Run objects are the raw dicts from the BioMate `list_runs` / `get_run` API.
"""
import argparse, json, subprocess, sys, io, csv

# Per-workflow correctness contracts (what a CORRECT run must emit). Extend as tasks are added.
CONTRACTS = {
    "merfish_spatial_analysis": {
        "required_outputs": ["spatial_domains.csv", "spatial_qc.json", "spatially_variable_genes.csv"],
        "json_keys": {"spatial_qc.json": []},  # keys required inside the JSON (empty = just valid JSON)
    },
    "Predict Admet Properties": {
        "required_outputs": ["toxicity_report.json", "predict_admet_properties_results.json", "qc_metrics.json"],
        "json_keys": {"toxicity_report.json": ["compounds_assessed", "per_compound", "toxicity"]},
    },
}


def _nf(run):
    ex = run.get("execution", {}) or {}
    return ex, (ex.get("nextflowStatus") or {})


def terminal_ok(run):
    ex, nf = _nf(run)
    if ex.get("status") != "completed":
        return False, f"status={ex.get('status')}"
    rc = nf.get("returncode")
    if rc not in (0, None):
        return False, f"returncode={rc}"
    if nf.get("status") not in ("succeeded", None):
        return False, f"nextflow={nf.get('status')}"
    return True, "terminal ok"


def result_outputs(run):
    _, nf = _nf(run)
    outs = nf.get("s3_output_files") or []
    return [o for o in outs if o.get("name") != "versions.yml"]


def s3_text(uri, n=4096):
    return subprocess.check_output(["aws", "s3", "cp", uri, "-"], stderr=subprocess.DEVNULL)[:n].decode("utf-8", "replace")


def content_ok(o):
    name, uri = o.get("name", ""), o.get("s3_uri", "")
    try:
        txt = s3_text(uri)
    except Exception as e:
        return False, f"fetch-fail({e})"
    if name.endswith(".json"):
        try:
            v = json.loads(txt)
            return (bool(v), "json ok" if v else "json empty")
        except Exception:
            return False, "json parse-fail"
    if name.endswith((".csv", ".tsv")):
        rows = list(csv.reader(io.StringIO(txt), delimiter="," if name.endswith(".csv") else "\t"))
        return (len(rows) >= 2, f"{len(rows)} rows")
    return (len(txt.strip()) > 0, "non-empty" if txt.strip() else "empty")


def grade_run(run, deep=False):
    wf = run.get("workflowName", "?")
    ok, why = terminal_ok(run)
    if not ok:
        return "FAIL", f"not-terminal-success: {why}"
    res = result_outputs(run)
    if not res:
        return "FAIL", "no result outputs (only versions/none)"
    if all((o.get("size") or 0) == 0 for o in res):
        return "FAIL", "all result outputs empty"
    con = CONTRACTS.get(wf)
    if con:
        have = {o.get("name") for o in res}
        missing = [r for r in con["required_outputs"] if r not in have]
        if missing:
            return "FAIL", f"missing required outputs: {missing}"
    if deep:
        for o in res:
            cok, cwhy = content_ok(o)
            if not cok:
                return "FAIL", f"content check failed on {o.get('name')}: {cwhy}"
        if con:
            for fn, keys in con.get("json_keys", {}).items():
                o = next((x for x in res if x.get("name") == fn), None)
                if o and keys:
                    try:
                        j = json.loads(s3_text(o["s3_uri"]))
                        miss = [k for k in keys if k not in j]
                        if miss:
                            return "FAIL", f"{fn} missing keys {miss}"
                    except Exception:
                        return "FAIL", f"{fn} unreadable"
    return "PASS", f"{len(res)} result outputs" + (" + content valid" if deep else "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", required=True, help="JSON array of run objects (from list_runs/get_run)")
    ap.add_argument("--deep", action="store_true", help="also validate output CONTENT from S3")
    a = ap.parse_args()
    runs = json.load(open(a.runs))
    if isinstance(runs, dict):
        runs = [runs]
    npass = 0
    print(f"{'VERDICT':7s} {'workflow':34s} run_id                                why")
    for r in runs:
        v, why = grade_run(r, deep=a.deep)
        npass += v == "PASS"
        print(f"{v:7s} {r.get('workflowName','?'):34s} {r.get('id','?')}  {why}")
    print(f"\n{npass}/{len(runs)} PASS")


if __name__ == "__main__":
    raise SystemExit(main())
