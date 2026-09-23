"""Step 2: per-task scorer on the family-disjoint corpus_eval.jsonl with the CORRECTED gold contracts
(routing = accept-set membership, not exact slug; param = schema-key recall; decompose = judge coverage).
Runs the trained model (direct 4-bit load). GPU. Usage:
  python eval_corpus.py --base <path> --adapter <path> --model qwen-small-full_v2 --out out.json
"""
import argparse, json, os, re, sys
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_removal import direct_load, call_direct, call_direct_batch, judge
from concurrent.futures import ThreadPoolExecutor
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
    import os as _os; rows = [json.loads(l) for l in open(_os.environ.get("EVAL_DIR", P) + "/corpus_eval.jsonl")]
    # cap per-task for a fast scorecard (8k rows x infer+judge = hours otherwise)
    lim = int(_os.environ.get("LIMIT_PER", "60")); seen = defaultdict(int); capped = []
    for r in rows:
        t = r.get("task", r.get("task_type", "?"))
        if seen[t] < lim: capped.append(r); seen[t] += 1
    rows = capped
    print(f"[eval_corpus] scoring {len(rows)} rows (<= {lim}/task) across {len(seen)} tasks", flush=True)
    # format-tolerant extraction: SFT-messages {messages,task} OR {input,target,task/task_type}
    items = []  # (user, teacher_str, task)
    for r in rows:
        if r.get("messages"):
            um = [m for m in r["messages"] if m.get("role") == "user"]
            am = [m for m in r["messages"] if m.get("role") == "assistant"]
            if not (um and am): continue
            user, teacher, task = um[-1]["content"], am[-1]["content"], r.get("task", "?")
        else:
            user, teacher, task = r.get("input"), r.get("target"), r.get("task", r.get("task_type", "?"))
        if not (user and teacher): continue
        items.append((user, teacher if isinstance(teacher, str) else json.dumps(teacher), task))
    # 1) BATCHED generation (Bx faster than one-at-a-time) with progress
    BS = int(_os.environ.get("GEN_BATCH", "12")); outs = []
    import traceback as _tb
    for i in range(0, len(items), BS):
        chunk = items[i:i + BS]
        try:
            outs.extend(call_direct_batch([u for u, _, _ in chunk], 300))
        except Exception as e:  # never crash the whole eval on a batch edge case — surface + degrade
            print(f"[eval_corpus] BATCH FAIL @ {i}: {type(e).__name__}: {e}", flush=True)
            _tb.print_exc()
            for u, _, _ in chunk:
                try: outs.append(call_direct(u, 300))
                except Exception as e2: print(f"  single fail: {e2}", flush=True); outs.append("")
        print(f"[eval_corpus] generated {min(i+BS,len(items))}/{len(items)}", flush=True)
    # 2) PARALLEL judge (923 sequential OpenAI calls -> concurrent) with progress
    def jrow(idx):
        _, tgt, _ = items[idx]
        return idx, judge([{"step": tgt}], outs[idx])
    scores = [0.0] * len(items); done = 0
    with ThreadPoolExecutor(max_workers=int(_os.environ.get("JUDGE_WORKERS", "16"))) as ex:
        for idx, s in ex.map(jrow, range(len(items))):
            scores[idx] = float(s); done += 1
            if done % 100 == 0: print(f"[eval_corpus] judged {done}/{len(items)}", flush=True)
    agg = defaultdict(lambda: [0.0, 0])
    for (_, _, task), s in zip(items, scores):
        agg[task][0] += s; agg[task][1] += 1
    per = {t: {"score": round(v[0] / max(v[1], 1), 3), "n": v[1]} for t, v in agg.items()}
    macro = round(sum(p["score"] for p in per.values()) / max(len(per), 1), 3)
    res = {"model": a.model, "macro_over_tasks": macro, "per_task": per, "eval": "family-disjoint corpus_eval"}
    json.dump(res, open(a.out, "w"), indent=2)
    print("CORPUS EVAL:", json.dumps(res))


if __name__ == "__main__":
    raise SystemExit(main())
