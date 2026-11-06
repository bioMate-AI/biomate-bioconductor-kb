#!/usr/bin/env python3
"""Submit the vina_virtual_screening_bench chain to dev, poll it, and print per-step status.

  python3 run_on_dev.py --actives 10 --decoys 30 [--full] [--out DIR]

Reads the chain definition from the LOCAL galaxy_ai_tools.db (the same rows that were synced to dev), stages the inputs in S3, logs in with the shared fixture
account (password only from the E2E_FIXTURE_PASSWORD environment variable; never stored in the repo), submits POST /api/workflows/chain, polls until a terminal
state, and writes chain_state.json. It does not register users. Standard library only; needs the aws CLI for the S3 staging.
"""
import argparse, csv, json, os, random, sqlite3, subprocess, sys, time, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "..", "..", "..", "backend", "database", "galaxy_ai_tools.db")
BASE = os.environ.get("BIOMATE_URL", "https://dev-public.biomate.ai")
BUCKET = "s3://biomate-nextflow-work/chain_bench/vina_egfr"
E2E_TOKEN = os.environ.get("E2E_TEST_TOKEN", "biomate-e2e-bypass-token-dev-only")


def http(method, path, token=None, body=None, timeout=60):
    h = {"Content-Type": "application/json", "x-e2e-test-token": E2E_TOKEN}
    if token:
        h["Authorization"] = "Bearer " + token
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode() if body is not None else None, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--actives", type=int, default=10)
    ap.add_argument("--decoys", type=int, default=30)
    ap.add_argument("--full", action="store_true", help="use the whole 296-compound library")
    ap.add_argument("--out", default=os.path.join(HERE, "run_out"))
    ap.add_argument("--max-wait", type=int, default=4 * 3600)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    rows = list(csv.DictReader(open(os.path.join(HERE, "data", "labels.csv"))))
    test = [r for r in rows if r["label"] in ("active", "decoy")]
    if a.full:
        lib = [r["smiles"] for r in test]
    else:
        rnd = random.Random(7)
        act = [r for r in test if r["label"] == "active"]
        approved = [r for r in act if any(k in r.get("source", "").lower() or k in r["id"].lower() for k in ("erlotinib", "gefitinib", "lapatinib", "afatinib", "osimertinib"))]
        rest = [r for r in act if r not in approved]
        rnd.shuffle(rest)
        chosen = (approved + rest)[:a.actives]
        dec = [r for r in test if r["label"] == "decoy"]; rnd.shuffle(dec)
        lib = [r["smiles"] for r in chosen + dec[:a.decoys]]
        rnd.shuffle(lib)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    lib_path = os.path.join(a.out, "library_run.smi"); open(lib_path, "w").write("\n".join(lib) + "\n")
    json.dump({"n_library": len(lib), "smiles": lib}, open(os.path.join(a.out, "library_run.json"), "w"))
    ref_path = os.path.join(HERE, "data", "reference_actives.smi")
    s3_lib, s3_ref = "%s/%s/library.smi" % (BUCKET, stamp), "%s/%s/reference_actives.smi" % (BUCKET, stamp)
    for src, dst in ((lib_path, s3_lib), (ref_path, s3_ref)):
        subprocess.check_call(["aws", "s3", "cp", src, dst, "--only-show-errors"])
    # chain definition from the local DB (identical rows to dev after the sync)
    c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(DB), uri=True)
    steps_db, conns = c.execute("select steps, connections from workflow_chains where name='vina_virtual_screening_bench'").fetchone()
    steps = []
    for s in json.loads(steps_db):
        fn = c.execute("select filename from workflows where id=?", (s["workflow_id"],)).fetchone()[0]
        params = dict(s.get("params_template") or {})
        if s["workflow_name"] == "pharmacophore_filtering":
            params.update({"reference_actives": s3_ref, "compound_library": s3_lib})
        steps.append({"workflow_name": s["workflow_name"], "workflow_id": s["workflow_id"], "nextflow_path": fn, "role": s.get("role"), "params": params})
    body = {"chain_name": "vina_virtual_screening_bench", "steps": steps, "connections": json.loads(conns)}
    json.dump(body, open(os.path.join(a.out, "submit_body.json"), "w"), indent=1)
    pw = os.environ.get("E2E_FIXTURE_PASSWORD")
    if not pw:
        sys.exit("E2E_FIXTURE_PASSWORD is not set; export it (it is never stored in the repo) and re-run")
    st, resp = http("POST", "/api/auth/login", body={"email": "lifeifei163361@163.com", "password": pw})
    token = resp.get("token")
    if not token:
        sys.exit("login failed: HTTP %s %s" % (st, str(resp)[:200]))
    st, resp = http("POST", "/api/workflows/chain", token, body)
    print("submit:", st, json.dumps(resp)[:600], flush=True)
    cid = resp.get("chain_run_id")
    if st >= 400 or not cid:
        sys.exit("submit failed")
    t0, last = time.time(), None
    while time.time() - t0 < a.max_wait:
        st, state = http("GET", "/api/workflows/chain/%s" % cid, token)
        summ = (state.get("status"), [(s.get("workflow_name"), s.get("status")) for s in state.get("steps", [])])
        if summ != last:
            print("%5ds" % (time.time() - t0), json.dumps(summ), flush=True); last = summ
        if state.get("status") in ("succeeded", "failed", "cancelled", "blocked"):
            json.dump(state, open(os.path.join(a.out, "chain_state.json"), "w"), indent=1)
            print("final:", state.get("status"), "wall_s=%d" % (time.time() - t0))
            for s in state.get("steps", []):
                print(" step", s.get("workflow_name"), s.get("status"), s.get("error") or "", s.get("handoff_warnings") or "", s.get("binding_problems") or "")
            print("chain_run_id:", cid)
            return 0 if state.get("status") == "succeeded" else 2
        time.sleep(30)
    print("timeout waiting; chain_run_id:", cid)
    return 3


if __name__ == "__main__":
    sys.exit(main())
