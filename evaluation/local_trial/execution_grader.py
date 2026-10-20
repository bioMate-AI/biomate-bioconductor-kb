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

# ── Per-workflow correctness contracts: a REGISTRY, not a frozen dict ────────────────────────────
# A contract states what a CORRECT run of a workflow / run-kind must emit. It is the ONE thing that is
# workflow-specific — the execution ladder (TIERS) and the tier→reward map (graded_run_store) are
# generic. `register_contract(...)` is the platform primitive: ANY workflow — not just the built-ins
# registered below — plugs a contract in WITHOUT editing this module (e.g. a new gromacs_pmx_fep or a
# small-molecule RBFE workflow calls it at import time), and its real runs then mint an objective,
# execution-verified reward through the same grader. (Layer C of the generic physics-in-loop framework;
# see docs/20261020_GENERIC_PHYSICS_IN_LOOP_FRAMEWORK_DESIGN.md.)
#
# A contract = {
#   "required_outputs": [basename, ...],   # a correct run must emit these   -> tier 'missing_required'
#   "json_keys": {basename: [key, ...]},   # keys required inside a JSON output (deep) -> 'content_invalid'
#   "validate": callable,                  # OPTIONAL extra deep check json_keys can't express (see below)
# }
CONTRACTS = {}


def register_contract(workflow_name, required_outputs=None, json_keys=None, validate=None):
    """Register (idempotent upsert) the correctness contract for a workflow / run-kind.

    required_outputs : output basenames a correct run must emit -> 'missing_required' if any are absent.
    json_keys        : {output_basename: [required keys]} checked in the deep path -> 'content_invalid'.
    validate         : OPTIONAL callable(run, result_outputs, fetch_text) -> (ok: bool, reason: str), an
                       extra deep-path content check for correctness the generic json_keys check cannot
                       express (e.g. an FEP ΔΔG cycle-closure / sign check). `fetch_text(uri)` fetches an
                       output's text. Built-in contracts register NO validate, so their grading is
                       byte-for-byte unchanged by this refactor.
    Returns the stored contract dict. Any module may call this to extend the platform's graded run-kinds
    without editing the grader core — the registry is the generic reward surface."""
    if not workflow_name or not isinstance(workflow_name, str):
        raise ValueError("register_contract: workflow_name must be a non-empty string")
    if validate is not None and not callable(validate):
        raise TypeError("register_contract: validate must be callable or None")
    con = {"required_outputs": list(required_outputs or []), "json_keys": dict(json_keys or {})}
    if validate is not None:
        con["validate"] = validate
    CONTRACTS[workflow_name] = con
    return con


def get_contract(workflow_name):
    """The registered contract for a workflow / run-kind, or None if none is registered."""
    return CONTRACTS.get(workflow_name)


# ── Built-in contracts (registered THROUGH the interface above; examples, not hard dependencies) ──
register_contract(
    "merfish_spatial_analysis",
    required_outputs=["spatial_domains.csv", "spatial_qc.json", "spatially_variable_genes.csv"],
    json_keys={"spatial_qc.json": []},  # keys required inside the JSON (empty = just valid JSON)
)
register_contract(
    "Predict Admet Properties",
    required_outputs=["toxicity_report.json", "predict_admet_properties_results.json", "qc_metrics.json"],
    json_keys={"toxicity_report.json": ["compounds_assessed", "per_compound", "toxicity"]},
)
# --- cyclic-peptide program (αvβ6 / PD-L1) synthesize->assay->execute runs ---
# A cofold run must emit a bound-complex structure; an MM-GBSA run a parseable binding-ΔG record; an
# assay-ingest run a target+ΔG record. These are EXECUTION facts (the run produced the expected artifact
# with the expected fields) — NOT a judgement of the ΔG's quality (that is score()'s reward, kept separate).
register_contract("cyclic_peptide_cofold", required_outputs=["complex.cif"])  # structure; content_ok enforces non-empty
register_contract(
    "cyclic_peptide_mmgbsa",
    required_outputs=["mmgbsa_result.json"],
    json_keys={"mmgbsa_result.json": ["dG_bind_kcal_mol", "target"]},
)
register_contract(
    "cyclic_peptide_assay",
    required_outputs=["assay_result.json"],
    json_keys={"assay_result.json": ["target", "binding_dG"]},
)


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
    if rc is None and nf.get("status") != "succeeded":
        return False, "missing execution success evidence"
    return True, "terminal ok"


def result_outputs(run):
    _, nf = _nf(run)
    outs = nf.get("s3_output_files") or []
    return [o for o in outs if o.get("name") != "versions.yml"]


def s3_text(uri):
    # Parse the complete artifact. Truncation can reject valid JSON or hide malformed tails.
    return subprocess.check_output(["aws", "s3", "cp", uri, "-"], stderr=subprocess.DEVNULL).decode("utf-8", "strict")


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


# Execution ladder tiers, worst -> best. A monotone tier is what the RLVR reward maps over
# (graded_run_store.reward_for_tier); the binary PASS/FAIL is just (tier == "pass").
TIERS = ["crashed", "no_outputs", "empty_outputs", "missing_required", "content_invalid", "pass"]


def grade_detailed(run, deep=False):
    """Objective grade as (verdict, reason, tier). verdict is PASS iff tier == 'pass'.
    Same checks/order as before; `tier` names how far the run got on the execution ladder so a
    reward can be dense (partial credit) instead of binary. No similarity, no LLM."""
    wf = run.get("workflowName", "?")
    ok, why = terminal_ok(run)
    if not ok:
        return "FAIL", f"not-terminal-success: {why}", "crashed"
    res = result_outputs(run)
    if not res:
        return "FAIL", "no result outputs (only versions/none)", "no_outputs"
    if all((o.get("size") or 0) == 0 for o in res):
        return "FAIL", "all result outputs empty", "empty_outputs"
    con = get_contract(wf)
    if con:
        have = {o.get("name") for o in res}
        missing = [r for r in con["required_outputs"] if r not in have]
        if missing:
            return "FAIL", f"missing required outputs: {missing}", "missing_required"
    if deep:
        for o in res:
            cok, cwhy = content_ok(o)
            if not cok:
                return "FAIL", f"content check failed on {o.get('name')}: {cwhy}", "content_invalid"
        # molecular-identity check: the reported per-compound MWs must match the intended molecules
        # (within tol). This makes a backend's SMILES-knowledge error EXECUTION-visible: a wrong SMILES
        # runs fine but yields the wrong MW -> FAIL.
        exp_mw = run.get("expect_mw")
        if exp_mw:
            rep = next((o for o in res if o.get("name") == "toxicity_report.json"), None)
            if not rep:
                return "FAIL", "expect_mw set but no toxicity_report.json", "content_invalid"
            try:
                j = json.loads(s3_text(rep["s3_uri"]))
                got = [c.get("mw") for c in j.get("per_compound", []) if c.get("mw") is not None]
            except Exception:
                return "FAIL", "toxicity_report.json unreadable for MW check", "content_invalid"
            for want in exp_mw:
                if not any(abs(float(g) - float(want)) <= 1.5 for g in got):
                    return "FAIL", f"wrong molecule: expected MW {want} not in reported {got} (bad SMILES)", "content_invalid"
        if con:
            for fn, keys in con.get("json_keys", {}).items():
                o = next((x for x in res if x.get("name") == fn), None)
                if o and keys:
                    try:
                        j = json.loads(s3_text(o["s3_uri"]))
                        miss = [k for k in keys if k not in j]
                        if miss:
                            return "FAIL", f"{fn} missing keys {miss}", "content_invalid"
                    except Exception:
                        return "FAIL", f"{fn} unreadable", "content_invalid"
            # Optional per-contract validator for correctness json_keys can't express (FEP cycle-closure,
            # ΔΔG sign, …). Absent on built-in contracts, so their behaviour is unchanged.
            vfn = con.get("validate")
            if vfn:
                try:
                    vok, vwhy = vfn(run, res, s3_text)
                except Exception as e:
                    return "FAIL", f"contract validate() raised: {e}", "content_invalid"
                if not vok:
                    return "FAIL", f"contract validate failed: {vwhy}", "content_invalid"
    return "PASS", f"{len(res)} result outputs" + (" + content valid" if deep else ""), "pass"


def grade_run(run, deep=False):
    """Backward-compatible (verdict, reason). Thin wrapper over grade_detailed."""
    v, why, _tier = grade_detailed(run, deep)
    return v, why


# ── CPU self-test of the contract REGISTRY ───────────────────────────────────────────────────────
# Proves (a) the built-in contracts survived the registry refactor and (b) a run-kind registered from
# OUTSIDE the grader core grades through the generic ladder (pass / missing_required / crashed) and the
# deep path honours json_keys + an optional validate() — i.e. any workflow can plug in. No AWS (S3 mocked).
def selftest():
    import unittest.mock as mock

    # (a) regression: every built-in contract is still registered after the refactor.
    for wf in ["merfish_spatial_analysis", "Predict Admet Properties",
               "cyclic_peptide_cofold", "cyclic_peptide_mmgbsa", "cyclic_peptide_assay"]:
        assert get_contract(wf), f"built-in contract {wf} lost after registry refactor"

    # (b) a NEW run-kind registered the way a gromacs_pmx_fep / RBFE workflow would, WITHOUT editing core.
    def _ddg_sane(run, res, fetch):  # an extra deep check json_keys can't express
        o = next((x for x in res if x.get("name") == "ddg_result.json"), None)
        v = json.loads(fetch(o["s3_uri"])).get("ddg_kcal_mol")
        return isinstance(v, (int, float)), f"ddg_kcal_mol={v!r}"
    register_contract("demo_rbfe_edge", required_outputs=["ddg_result.json"],
                      json_keys={"ddg_result.json": ["ddg_kcal_mol", "edge"]}, validate=_ddg_sane)
    assert get_contract("demo_rbfe_edge"), "newly-registered contract not retrievable"

    import graded_run_store as GRS  # lazy (GRS imports us) — for the tier→reward endpoints
    assert GRS.reward_for_tier("pass") == 1.00 and GRS.reward_for_tier("crashed") == 0.00

    def ex(files, status="completed"):
        return {"status": status,
                "nextflowStatus": {"status": "succeeded" if status == "completed" else "failed",
                                   "returncode": 0, "s3_output_files": files}}
    f = lambda name, size: {"name": name, "size": size, "s3_uri": f"s3://fixture/{name}"}

    print("=== registry selftest: a run-kind registered OUTSIDE the core grades on the generic ladder ===")
    l1 = [
        ("pass",             {"id": "e_pass",  "workflowName": "demo_rbfe_edge", "execution": ex([f("ddg_result.json", 256)])}),
        ("missing_required", {"id": "e_miss",  "workflowName": "demo_rbfe_edge", "execution": ex([f("run.log", 99)])}),
        ("crashed",          {"id": "e_crash", "workflowName": "demo_rbfe_edge", "execution": ex([f("ddg_result.json", 256)], status="running")}),
    ]
    for exp_tier, run in l1:
        v, why, tier = grade_detailed(run, deep=False)
        rw = GRS.reward_for_tier(tier)
        print(f"  {run['id']:8s} tier={tier:16s} verdict={v:4s} reward={rw:.2f}  ({why})")
        assert tier == exp_tier, f"{run['id']}: tier {tier} != {exp_tier}"
    assert GRS.reward_for_tier("pass") == 1.00 and GRS.reward_for_tier("missing_required") == 0.45

    print("=== deep path on the registered contract: json_keys + validate() (S3 mocked) ===")
    runp = {"id": "e_deep", "workflowName": "demo_rbfe_edge", "execution": ex([f("ddg_result.json", 256)])}
    deep_cases = [
        ('{"ddg_kcal_mol": -1.2, "edge": "A->B"}', "pass",            "PASS", "valid"),
        ('{"edge": "A->B"}',                       "content_invalid", "FAIL", "missing json key"),
        ('{"ddg_kcal_mol": "oops", "edge": "A->B"}', "content_invalid", "FAIL", "validate() rejects"),
    ]
    for payload, exp_tier, exp_v, label in deep_cases:
        with mock.patch.object(sys.modules[__name__], "s3_text", return_value=payload):
            v, why, tier = grade_detailed(runp, deep=True)
        print(f"  {label:18s} tier={tier:16s} verdict={v:4s}  ({why})")
        assert tier == exp_tier and v == exp_v, f"{label}: {tier}/{v} != {exp_tier}/{exp_v} ({why})"

    print("\nSELFTEST PASS — built-in contracts preserved; a contract registered outside the core grades"
          " on the generic ladder (pass=1.00 / missing_required=0.45 / crashed=0.00) and the deep path"
          " honours json_keys + validate(). The reward surface is generic over any registered run-kind.")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", help="JSON array of run objects (from list_runs/get_run)")
    ap.add_argument("--deep", action="store_true", help="also validate output CONTENT from S3")
    ap.add_argument("--selftest", action="store_true", help="CPU self-test of the contract registry (no AWS)")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not a.runs:
        ap.error("one of --runs / --selftest is required")
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
