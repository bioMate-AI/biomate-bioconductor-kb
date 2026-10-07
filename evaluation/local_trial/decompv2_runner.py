#!/usr/bin/env python3
"""Run the held-out dependency-graph benchmark (evaluation/datasets/decomposition_v2) against an
OpenAI-compatible endpoint (the harness_shim serving one reconstructed arm) and score it with the
benchmark's own graph-aware scorer.

Honest-metric path for docs/20260912_onprem_llm/20261006_DECOMPOSITION_ERROR_ANALYSIS.md: replaces
the coarse 4-class `structure_accuracy` with node-F1 + edge-F1 + per-class structure, focused on the
parallel/mixed classes that were 0/8 in the error analysis.

Prompt convention is IDENTICAL to public_export/run_baseline.py task_decomposition:
    prompt = f"{instr}\n\nINPUT:\n{query}"   ;   parse = first JSON list in the reply
so base and SFT arms see the same prompt and the delta is attributable to the adapter alone.

Usage:
  python3 decompv2_runner.py --bench decomposition_v2.jsonl --scorer score.py \
      --model <label> --base-url http://127.0.0.1:8000/v1 --key-env OPENAI_API_KEY \
      --preds-out preds_<label>.jsonl --score-out score_<label>.json
"""
from __future__ import annotations
import argparse, json, os, re, sys, time, importlib.util


def load(path):
    return [json.loads(l) for l in open(path) if l.strip()]


def parse_plan(txt):
    m = re.search(r"\[.*\]", txt or "", re.S)
    if not m:
        return []
    try:
        p = json.loads(m.group())
        return p if isinstance(p, list) else []
    except Exception:
        return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bench", required=True)
    ap.add_argument("--scorer", required=True, help="path to decomposition_v2/score.py")
    ap.add_argument("--model", required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--key-env", default="OPENAI_API_KEY")
    ap.add_argument("--preds-out", required=True)
    ap.add_argument("--score-out", required=True)
    ap.add_argument("--max-tokens", type=int, default=1024)
    # verifier re-ranker (STAGE-2 option #3): sample N per item at temp>0 from the SAME served
    # policy, keep the gold-free catalog-verifier best. Lift vs greedy = honest real-sample re-rank.
    ap.add_argument("--rerank-n", type=int, default=0, help="N samples per item (0 disables rerank)")
    ap.add_argument("--rerank-temp", type=float, default=0.8)
    ap.add_argument("--db", default=None, help="galaxy_ai_tools.db for the structural verifier")
    ap.add_argument("--rerank-preds-out", default=None)
    ap.add_argument("--rerank-score-out", default=None)
    ap.add_argument("--rerank-only", action="store_true",
                    help="skip the greedy pass (greedy already run+uploaded); only sample+rerank+score")
    a = ap.parse_args()

    from openai import OpenAI
    client = OpenAI(base_url=a.base_url, api_key=os.environ.get(a.key_env, "local-shim"))

    rows = load(a.bench)
    # score via the benchmark's own scorer (imported so we don't shell out)
    spec = importlib.util.spec_from_file_location("decompv2_score", a.scorer)
    sc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sc)
    gold_by_id = {r["id"]: r for r in rows}

    if not a.rerank_only:
        preds = []
        t_all = time.time()
        with open(a.preds_out, "w") as f:
            for i, r in enumerate(rows):
                prompt = f"{r['instr']}\n\nINPUT:\n{r['query']}"
                plan = []
                for attempt in range(3):
                    try:
                        resp = client.chat.completions.create(
                            model=a.model,
                            messages=[{"role": "user", "content": prompt}],
                            max_completion_tokens=a.max_tokens, temperature=0.0)
                        plan = parse_plan(resp.choices[0].message.content)
                        break
                    except Exception as e:
                        if attempt == 2:
                            sys.stderr.write(f"[{r['id']}] ERR {e}\n")
                        else:
                            time.sleep(2 * (attempt + 1))
                rec = {"id": r["id"], "pred": plan}
                preds.append(rec)
                f.write(json.dumps(rec) + "\n")
                if (i + 1) % 25 == 0:
                    sys.stderr.write(f"  {i+1}/{len(rows)}\n")
        sys.stderr.write(f"wrote {len(preds)} preds -> {a.preds_out} ({int(time.time()-t_all)}s)\n")
        pred_by_id = {r["id"]: r["pred"] for r in preds}
        out = sc.score_batch(gold_by_id, pred_by_id)
        with open(a.score_out, "w") as f:
            json.dump(out, f, indent=2)
        print("=== GREEDY ==="); print(json.dumps(out, indent=2))

    # ---- verifier re-ranker on REAL sampled candidates from this same served policy ----
    if a.rerank_n and a.rerank_n > 0 and a.db:
        import decomp_reward as RW
        import decomp_reranker as RR
        catalog = RW.load_catalog(a.db)
        sys.stderr.write(f"rerank: catalog n={catalog['n']} N={a.rerank_n} T={a.rerank_temp}\n")
        rpreds = {}
        rpath = a.rerank_preds_out or (a.preds_out.replace(".jsonl", "_rerank.jsonl"))
        t_r = time.time()
        with open(rpath, "w") as f:
            for i, r in enumerate(rows):
                prompt = f"{r['instr']}\n\nINPUT:\n{r['query']}"
                try:
                    best = RR.rerank_from_endpoint(client, a.model, prompt, catalog,
                                                   n=a.rerank_n, temperature=a.rerank_temp,
                                                   max_tokens=a.max_tokens)
                except Exception as e:
                    sys.stderr.write(f"[{r['id']}] rerank ERR {e}\n"); best = []
                rpreds[r["id"]] = best
                f.write(json.dumps({"id": r["id"], "pred": best}) + "\n")
                if (i + 1) % 25 == 0:
                    sys.stderr.write(f"  rerank {i+1}/{len(rows)}\n")
        sys.stderr.write(f"rerank done ({int(time.time()-t_r)}s)\n")
        rout = sc.score_batch(gold_by_id, rpreds)
        rsout = a.rerank_score_out or (a.score_out.replace(".json", "_rerank.json"))
        with open(rsout, "w") as f:
            json.dump(rout, f, indent=2)
        print("=== VERIFIER-RERANK ==="); print(json.dumps(rout, indent=2))


if __name__ == "__main__":
    main()
