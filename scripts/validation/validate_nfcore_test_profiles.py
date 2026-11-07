#!/usr/bin/env python3
"""Run nf-core pipelines on their own `-profile test` data through BioMate's product execution path on AWS Batch.

Evidence for re-enabling catalog rows that are executable=0: a row is re-enabled only if its pipeline completes
(rc 0) on the pipeline's test profile with real outputs. Uses the fixture account (login once), POST
/api/workflows/search → /api/workflows/execute with params.profile = "test,aws" (the executor pops `profile` from
params), then polls GET /api/workflows/runs/{runId}. Nothing user-supplied is run.

Usage: scripts/validation/validate_nfcore_test_profiles.py <out.json> nf-core/chipseq nf-core/atacseq ...
"""
import json, os, ssl, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "routing_eval"))
import route_eval as R  # noqa: E402 — shared login/post helpers (fixture account, password from local file)

BASE = R.BASE
CTX = ssl.create_default_context()


def call(method, path, jwt, body=None, timeout=120):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", "Cookie": f"biomate_token={jwt}",
                                          "Authorization": f"Bearer {jwt}"})
    try:
        with urllib.request.urlopen(req, context=CTX, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read()[:20000].decode(errors="replace")}
    except Exception as e:  # noqa: BLE001
        return -1, {"error": str(e)[:300]}


# Values the pre-launch required-param gate checks but `-profile test` would set from the pipeline's own
# conf/test.config (copied verbatim from those files on dev; pipelines_testdata_base_path expanded to its default).
TD = "https://raw.githubusercontent.com/nf-core/test-datasets/"
TEST_PARAMS = {
    "nf-core/chipseq": {"input": TD + "chipseq/samplesheet/v2.1/samplesheet_test.csv", "read_length": 50,
                        "fasta": TD + "atacseq/reference/genome.fa", "gtf": TD + "atacseq/reference/genes.gtf"},
    "nf-core/atacseq": {"input": TD + "atacseq/samplesheet/v2.0/samplesheet_test.csv", "read_length": 50,
                        "fasta": TD + "atacseq/reference/genome.fa", "gtf": TD + "atacseq/reference/genes.gtf"},
    "nf-core/scrnaseq": {"input": "https://github.com/nf-core/test-datasets/raw/scrnaseq/samplesheet-2-0.csv",
                         "fasta": "https://github.com/nf-core/test-datasets/raw/scrnaseq/reference/GRCm38.p6.genome.chr19.fa",
                         "gtf": "https://github.com/nf-core/test-datasets/raw/scrnaseq/reference/gencode.vM19.annotation.chr19.gtf",
                         "aligner": "star", "protocol": "10XV2"},
    "nf-core/mag": {"input": TD + "mag/samplesheets/samplesheet.multirun.v4.csv"},
    "nf-core/ampliseq": {"input": TD + "ampliseq/samplesheets/Samplesheet.tsv", "metadata": TD + "ampliseq/samplesheets/Metadata.tsv"},
    # cageseq 1.0.x's conf/test.config still points at test-datasets/cageseq/{reference,testdata}/…; upstream moved
    # the same files into versioned v1/ folders (old paths 404, new ones 200, checked 2026-11-06).
    "nf-core/cageseq": {"fasta": TD + "cageseq/reference/v1/chr_sub.fasta", "gtf": TD + "cageseq/reference/v1/chr_sub.gtf",
                        "input_paths": [["cage 1", TD + "cageseq/testdata/v1/cage1.fastq.gz"],
                                        ["cage 2", TD + "cageseq/testdata/v1/cage2.fastq.gz"]]},
    "nf-core/scdownstream": {"input": TD.rstrip("/") + "/4d8b9974c14cf11280d29bfe16f94e284793e499/samplesheet.csv"},
}


# Directory holding each deployed pipeline's <name>/conf/test.config and <name>/nextflow.config, copied from the
# Galaxy container (/app/nf-core-workflows). The launch gate requires the params the pipeline's schema requires
# (e.g. input); `-profile test` would set them, but the gate runs before Nextflow, so they are read from here.
TEST_CONFIG_DIR = os.environ.get("NFCORE_TEST_CONFIG_DIR", "")


def _test_profile_values(name, wanted):
    """{param: value} for `wanted` params as conf/test.config sets them (strings, string lists)."""
    import re
    short = name.split("/")[-1]
    try:
        test_cfg = open(os.path.join(TEST_CONFIG_DIR, short, "conf", "test.config")).read()
    except OSError:
        return {}
    try:
        base = re.search(r"pipelines_testdata_base_path\s*=\s*['\"]([^'\"]+)['\"]",
                         open(os.path.join(TEST_CONFIG_DIR, short, "nextflow.config")).read()).group(1)
    except (OSError, AttributeError):
        base = TD

    def expand(v):
        # ${projectDir} is the pipeline's directory in the Galaxy container, where the executor runs it.
        return (v.replace("${params.pipelines_testdata_base_path}", base)
                 .replace("${projectDir}", f"/app/nf-core-workflows/{short}"))

    out = {}
    for p in wanted:
        m = re.search(rf"(?m)^\s*{re.escape(p)}\s*=\s*(.+)$", test_cfg)
        if not m:
            continue
        rhs = m.group(1).strip()
        if rhs.startswith("["):
            body = test_cfg[m.start(1):test_cfg.index("]", m.start(1))]
            out[p] = [expand(x) for x in re.findall(r"['\"]([^'\"]+)['\"]", body)]
            continue
        pm = re.match(r"params\.pipelines_testdata_base_path\s*\+\s*['\"]([^'\"]+)['\"]", rhs)
        if pm:
            out[p] = base + pm.group(1)
            continue
        sm = re.match(r"['\"]([^'\"]*)['\"]", rhs)
        if sm:
            out[p] = expand(sm.group(1))
    return out


def run_one(jwt, name, max_wait_s=5400):
    st, s = call("POST", "/api/workflows/search", jwt, {"query": name, "limit": 3, "defer_param_prefill": True})
    hits = (s.get("workflows") or s.get("results") or []) if isinstance(s, dict) else []
    wf = next((h.get("workflow_ga") or h for h in hits if (h.get("name") or (h.get("workflow_ga") or {}).get("name")) == name), None)
    if wf is None and isinstance(s, dict) and s.get("workflow_ga"):
        wf = s["workflow_ga"]
    if not wf or (wf.get("name") != name):
        return {"name": name, "status": "not_found", "search_http": st, "search_keys": list(s)[:8] if isinstance(s, dict) else None}
    # Only the profile and the gate-required values: any other value sent on the command line
    # overrides the test profile (proteomicslfq: add_decoys=true on its target-decoy database).
    # NFCORE_EXTRA_PARAMS='{"nf-core/x": {"param": value}}' adds diagnostic params (e.g. a debug level).
    extra = json.loads(os.environ.get("NFCORE_EXTRA_PARAMS", "{}")).get(name, {})
    params = {**TEST_PARAMS.get(name, {}), **extra, "profile": "test,aws"}
    wf = {**wf, "parameters": params}
    st, e = call("POST", "/api/workflows/execute", jwt, {"workflowDefinition": wf, "params": params}, timeout=300)
    if st == 400 and "missing_required_params" in str(e) and TEST_CONFIG_DIR:
        try:
            missing = [m["name"] for m in json.loads(e["error"]).get("missing", [])]
        except (KeyError, ValueError, TypeError):
            missing = []
        fill = _test_profile_values(name, missing)
        if fill:
            params = {**params, **fill}
            wf = {**wf, "parameters": params}
            st, e = call("POST", "/api/workflows/execute", jwt, {"workflowDefinition": wf, "params": params}, timeout=300)
    run_id = e.get("runId") if isinstance(e, dict) else None
    if not run_id:
        return {"name": name, "status": "launch_failed", "http": st, "detail": e}
    t0 = time.time(); last = {}
    while time.time() - t0 < max_wait_s:
        time.sleep(60)
        # Poll the status route the UI polls: it reconciles the run against Galaxy's Nextflow state.
        # The bare run record only changes when something reads that route (the reaper was a no-op
        # until 49e071207, so a finished run read as 'running' for 80+ min).
        st, stat = call("GET", f"/api/workflows/runs/{run_id}/status", jwt)
        if str((stat or {}).get("status", "")).lower() in ("completed", "succeeded", "success", "failed", "error", "cancelled", "interrupted"):
            break
    st, last = call("GET", f"/api/workflows/runs/{run_id}", jwt)
    ex = (last or {}).get("execution") or {}
    return {"name": name, "runId": run_id, "status": ex.get("status"), "exit_code": ex.get("exit_code", ex.get("rc")),
            "output_files": len(ex.get("output_files") or last.get("output_files") or []),
            "error": (ex.get("errorMessage") or ex.get("error") or "")[:400], "minutes": round((time.time() - t0) / 60, 1)}


def main():
    out, names = sys.argv[1], sys.argv[2:]
    st, body = R.post("/api/auth/login", {"email": R.EMAIL, "password": R.fixture_password()})
    jwt = json.loads(body).get("token", "") if st == 200 else ""
    if len(jwt) < 50:
        sys.exit(f"login failed: HTTP {st}")
    from concurrent.futures import as_completed
    res = []
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    # NFCORE_VALIDATE_PARALLEL bounds concurrent pipelines: Batch hosts have a 30 GB root volume shared by
    # every image and task, and 15 concurrent nf-core runs filled it ("no space left on device", 2026-11-06).
    with ThreadPoolExecutor(min(len(names), int(os.environ.get("NFCORE_VALIDATE_PARALLEL", "2")))) as ex:
        futs = [ex.submit(run_one, jwt, n) for n in names]
        for f in as_completed(futs):   # each result written as soon as that run finishes
            r = f.result(); res.append(r); print(json.dumps(r)[:300], flush=True)
            json.dump(res, open(out, "w"), indent=1)


if __name__ == "__main__":
    main()
