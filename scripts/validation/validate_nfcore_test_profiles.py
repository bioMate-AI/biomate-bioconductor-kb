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
        return e.code, {"error": e.read()[:500].decode(errors="replace")}
    except Exception as e:  # noqa: BLE001
        return -1, {"error": str(e)[:300]}


def run_one(jwt, name, max_wait_s=5400):
    st, s = call("POST", "/api/workflows/search", jwt, {"query": name, "limit": 3, "defer_param_prefill": True})
    hits = (s.get("workflows") or s.get("results") or []) if isinstance(s, dict) else []
    wf = next((h.get("workflow_ga") or h for h in hits if (h.get("name") or (h.get("workflow_ga") or {}).get("name")) == name), None)
    if wf is None and isinstance(s, dict) and s.get("workflow_ga"):
        wf = s["workflow_ga"]
    if not wf or (wf.get("name") != name):
        return {"name": name, "status": "not_found", "search_http": st, "search_keys": list(s)[:8] if isinstance(s, dict) else None}
    params = {**(wf.get("parameters") or {}), "profile": "test,aws"}
    wf = {**wf, "parameters": params}
    st, e = call("POST", "/api/workflows/execute", jwt, {"workflowDefinition": wf, "params": params}, timeout=300)
    run_id = e.get("runId") if isinstance(e, dict) else None
    if not run_id:
        return {"name": name, "status": "launch_failed", "http": st, "detail": e}
    t0 = time.time(); last = {}
    while time.time() - t0 < max_wait_s:
        time.sleep(60)
        st, last = call("GET", f"/api/workflows/runs/{run_id}", jwt)
        ex = (last or {}).get("execution") or {}
        if str(ex.get("status", "")).lower() in ("completed", "succeeded", "success", "failed", "error", "cancelled"):
            break
    ex = (last or {}).get("execution") or {}
    return {"name": name, "runId": run_id, "status": ex.get("status"), "exit_code": ex.get("exit_code", ex.get("rc")),
            "output_files": len(ex.get("output_files") or last.get("output_files") or []),
            "error": (ex.get("error") or "")[:400], "minutes": round((time.time() - t0) / 60, 1)}


def main():
    out, names = sys.argv[1], sys.argv[2:]
    st, body = R.post("/api/auth/login", {"email": R.EMAIL, "password": R.fixture_password()})
    jwt = json.loads(body).get("token", "") if st == 200 else ""
    if len(jwt) < 50:
        sys.exit(f"login failed: HTTP {st}")
    with ThreadPoolExecutor(len(names)) as ex:
        res = list(ex.map(lambda n: run_one(jwt, n), names))
    json.dump(res, open(out, "w"), indent=1)
    for r in res:
        print(json.dumps(r)[:300])


if __name__ == "__main__":
    main()
