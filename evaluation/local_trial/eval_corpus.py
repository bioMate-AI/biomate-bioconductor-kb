"""Step 2: per-task scorer on the family-disjoint corpus_eval.jsonl with the CORRECTED gold contracts
(routing = accept-set membership, not exact slug; param = schema-key recall; decompose = judge coverage).
Runs the trained model (direct 4-bit load). GPU. Usage:
  python eval_corpus.py --base <path> --adapter <path> --model qwen-small-full_v2 --out out.json
"""
import argparse, json, os, re, sys
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_removal import direct_load, call_direct, judge
P = "/Users/kky/biomate-review/docs/20260912_onprem_llm/data_pool_v2"


def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


PROMPT = {
    "routing": lambda r: f"You are BioMate. Name the single best workflow for this request. Reply ONLY the workflow name.\n\nRequest: {r['input']}",
    "param": lambda r: f"You are BioMate. Extract the parameters this request implies as key: value lines. Do not invent.\n\nRequest: {r['input']}",
    "wfgen": lambda r: f"You are BioMate. Name the workflow category/domain for this request. Reply ONLY the category.\n\nRequest: {r['input']}",
    "autofix": lambda r: f"You are BioMate. Classify this pipeline failure into ONE fix category. Reply ONLY the category.\n\nError:\n{r['input'][:1200]}",
    "decompose": lambda r: f'You are BioMate. Decompose into an ordered sub-task plan. Reply ONLY a JSON list of {{"sub_task":...,"order":N}}.\n\nRequest: {r["input"]}',
    "knowledge_qa": lambda r: f"You are BioMate. Answer concisely and factually.\n\nQuestion: {r['input']}",
}


def score(r, out):
    t, o = r["task"], norm(out)
    if t == "routing":
        acc = r.get("accept_set") or [r["target"]]
        return 1.0 if any(norm(a) in o for a in acc) else 0.0
    if t == "param":
        g = r["target"] if isinstance(r["target"], dict) else {}
        if not g: return None
        return sum(1 for k, v in g.items() if norm(v) and norm(v) in o) / len(g)
    if t in ("wfgen", "autofix"):
        return 1.0 if norm(r["target"]) in o else 0.0
    if t == "decompose":
        g = r["target"] if isinstance(r["target"], list) else []
        return judge([{"step": s.get("sub_task", s) if isinstance(s, dict) else s} for s in g], out) if g else None
    if t == "knowledge_qa":
        return judge([{"step": r["target"]}], out)  # semantic coverage of the gold answer
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--adapter", default="")
    ap.add_argument("--model", default="model"); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    direct_load(a.base, a.adapter or None)
    rows = [json.loads(l) for l in open(f"{P}/corpus_eval.jsonl")]
    agg = defaultdict(lambda: [0.0, 0])
    for r in rows:
        mk = PROMPT.get(r["task"])
        if not mk: continue
        out = call_direct(mk(r), 300)
        if out is None: continue
        s = score(r, norm(out) if r["task"] in () else out)
        if s is None: continue
        agg[r["task"]][0] += float(s); agg[r["task"]][1] += 1
    per = {t: {"score": round(v[0] / max(v[1], 1), 3), "n": v[1]} for t, v in agg.items()}
    macro = round(sum(p["score"] for p in per.values()) / max(len(per), 1), 3)
    res = {"model": a.model, "macro_over_tasks": macro, "per_task": per, "eval": "family-disjoint corpus_eval"}
    json.dump(res, open(a.out, "w"), indent=2)
    print("CORPUS EVAL:", json.dumps(res))


if __name__ == "__main__":
    raise SystemExit(main())
