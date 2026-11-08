"""GOLD-STANDARD routing scorer — NOT teacher-fidelity. Scores against DB-verified correct workflows
(realbio+dbtest candidate-grounded, accept-set = correct U acceptable_alts U accept_sets.json).
This is the score() routing contract: 1.0 if the model's pick is in the accept-set, else 0.0.
Usage: python eval_gold.py --base <p> --adapter <p> --model <name> --evalfile gold_routing_eval.jsonl --out o.json
"""
import argparse, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_removal import direct_load, call_direct_batch


def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


def answer_of(out):  # strip a Qwen3 <think>...</think> trace; keep the final answer
    if "</think>" in out: out = out.rsplit("</think>", 1)[1]
    return out.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--adapter", default="")
    ap.add_argument("--model", default="model"); ap.add_argument("--out", required=True)
    ap.add_argument("--evalfile", required=True)
    a = ap.parse_args()
    direct_load(a.base, a.adapter or None)
    rows = [json.loads(l) for l in open(a.evalfile)]
    lim = int(os.environ.get("LIMIT", "0"))
    if lim: rows = rows[:lim]
    prompts = []
    for r in rows:
        cands = "\n".join(f"- {c}" for c in r["candidates"])
        prompts.append("You are BioMate. Choose the single best workflow for this request from the "
                       f"candidates. Reply ONLY the exact workflow name.\n\nRequest: {r['query']}\n\nCandidates:\n{cands}")
    BS = int(os.environ.get("GEN_BATCH", "24")); outs = []
    for i in range(0, len(prompts), BS):
        outs.extend(call_direct_batch(prompts[i:i + BS], 256))
        print(f"[gold] {min(i+BS,len(prompts))}/{len(prompts)}", flush=True)
    hit = exact = 0
    for r, o in zip(rows, outs):
        ans = norm(answer_of(o))
        acc = r["accept"]
        if any(norm(x) in ans for x in acc): hit += 1        # accept-set membership (functional equivalence)
        if norm(r["gold"]) in ans: exact += 1                # stricter: exact DB gold
    res = {"model": a.model, "task": "routing_gold", "n": len(rows),
           "accept_set_accuracy": round(hit / max(len(rows), 1), 3),
           "exact_gold_accuracy": round(exact / max(len(rows), 1), 3),
           "eval": "realbio+dbtest candidate-grounded, DB-verified gold"}
    json.dump(res, open(a.out, "w"), indent=2)
    print("GOLD ROUTING:", json.dumps(res))


if __name__ == "__main__":
    raise SystemExit(main())
