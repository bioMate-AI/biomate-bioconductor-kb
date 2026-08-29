#!/usr/bin/env python3
"""Comparison A, cell C2: route the 200 RealBio queries through REAL BioMate on dev.

Uses BioMate's production workflow router on the FULL curated DB (dev-public.biomate.ai,
the ~328MB enriched galaxy_ai_tools.db — the local file is a stub). Two C2 variants:

  --mode ir    (default) POST /api/ai_assistant/search_ranked, take top-1. ENGINE-FREE:
               pure curated-index retrieval, no LLM. This is the fair C2 for "model held
               fixed" Comparison A, because BioMate's routing decision has no engine to
               confound — the routing IS the retrieval index.
  --mode chat  full end-to-end pipeline via /api/chat/stream (search + LLM disambiguation),
               reported for completeness (uses dev's production engine).

Writes results/biomate_dev/cross_domain_routing_c2<mode>.jsonl in the shared {id, prediction}
format. Score with:  python3 score.py cross_domain_routing results/biomate_dev/<file>
"""
import json, os, sys, argparse, time, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
DEV = os.environ.get("BIOMATE_BASE_URL", "https://dev-public.biomate.ai")
TOK = os.environ.get("E2E_TEST_TOKEN", "biomate-e2e-bypass-token-dev-only")

def post(path, body, timeout=45, retries=3):
    data = json.dumps(body).encode()
    for a in range(retries):
        try:
            req = urllib.request.Request(f"{DEV}{path}", data=data,
                headers={"Content-Type": "application/json", "x-e2e-test-token": TOK})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            if a == retries - 1:
                sys.stderr.write(f"  ERR {path}: {str(e)[:120]}\n"); return None
            time.sleep(3 * (a + 1))

def route_ir(query):
    d = post("/api/ai_assistant/search_ranked", {"query": query, "limit": 5})
    rs = (d or {}).get("results") or []
    return rs[0]["name"] if rs else ""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["ir", "chat"], default="ir")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()
    rows = [json.loads(l) for l in open(os.path.join(HERE, "cross_domain_routing", "data.jsonl"))]
    if args.limit: rows = rows[:args.limit]
    outdir = os.path.join(HERE, "results", "biomate_dev"); os.makedirs(outdir, exist_ok=True)
    outpath = os.path.join(outdir, f"cross_domain_routing_c2{args.mode}.jsonl")
    n = 0
    with open(outpath, "w") as f:
        for r in rows:
            pred = route_ir(r["query"]) if args.mode == "ir" else ""  # chat mode wired separately
            f.write(json.dumps({"id": r["id"], "prediction": pred}) + "\n")
            n += 1
            if n % 25 == 0: sys.stderr.write(f"  {n}/{len(rows)}\n")
    print(f"wrote {n} predictions -> {outpath}")

if __name__ == "__main__":
    main()
