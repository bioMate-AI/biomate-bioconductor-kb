"""Corpus-scale quality pass on the SFT train/eval sets — confirms the committee's sample-level findings
at scale (no LLM, fast). Per task: truncation, CI/CD-harness leakage, answer-leakage (gold derivable from
question), duplication, templating (very-short answers). Usage:
  python audit_sft_quality.py --train multitask_sft_big.jsonl --eval corpus_eval_big.jsonl --out audit.json
"""
import argparse, json, re, collections

CI_LEAK = re.compile(r"/rlib|rlib shadow|flagged as runnable|test.environment|synthetic fixture|"
                     r"test.data limitation|benchmark runner|runnable for BioMate|test harness|fixture", re.I)
DANGLING = {"of", "the", "and", "to", "a", "an", "in", "on", "for", "with", "or", "each", "run", "using",
            "from", "by", "as", "is", "are", "that", "this", "which", "at", "into", "your", "these"}
ENDERS = set('.!?)]}:"\'`%')


def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()
def toks(s): return set(norm(s).split())


def truncated(a):
    a = a.rstrip()
    if not a: return True
    if a[-1] in ENDERS or a[-1].isdigit(): return False
    last = re.split(r"\s+", a)[-1].lower().strip(",;")
    return last in DANGLING or a[-1] == ","   # clearly mid-sentence


def extract(r):
    if r.get("messages"):
        m = {x["role"]: x["content"] for x in r["messages"]}
        return m.get("user", ""), m.get("assistant", "")
    return r.get("input", "") or "", (r.get("target", "") if isinstance(r.get("target"), str) else json.dumps(r.get("target", "")))


def audit(rows, label):
    per = collections.defaultdict(lambda: {"n": 0, "trunc": 0, "ci": 0, "leak": 0, "leak_denom": 0,
                                           "short": 0, "alen": 0})
    seen_a = collections.Counter(); seen_pair = collections.Counter()
    cross_ans_task = collections.defaultdict(set)
    LEAKY = {"workflow_routing", "tool_recommendation", "workflow_generation", "wfgen", "routing"}
    for r in rows:
        t = r.get("task", r.get("task_type", "?"))
        u, a = extract(r)
        d = per[t]; d["n"] += 1; d["alen"] += len(a)
        if truncated(a): d["trunc"] += 1
        if CI_LEAK.search(u + " " + a): d["ci"] += 1
        if len(a.strip()) < 40: d["short"] += 1
        if t in LEAKY:
            d["leak_denom"] += 1
            # gold answer derivable from the question (answer tokens subset of question tokens)
            at, ut = toks(a), toks(u)
            if at and at <= ut: d["leak"] += 1
        seen_a[norm(a)[:200]] += 1
        seen_pair[(norm(u)[:120], norm(a)[:120])] += 1
        cross_ans_task[norm(a)[:200]].add(t)
    dup_ans = sum(c - 1 for c in seen_a.values() if c > 1)
    dup_pair = sum(c - 1 for c in seen_pair.values() if c > 1)
    cross = sum(1 for ts in cross_ans_task.values() if len(ts) > 1)
    out = {"label": label, "total": len(rows), "exact_dup_answers": dup_ans, "exact_dup_pairs": dup_pair,
           "same_answer_multiple_tasks": cross, "per_task": {}}
    for t, d in sorted(per.items(), key=lambda x: -x[1]["n"]):
        n = d["n"]
        out["per_task"][t] = {"n": n, "trunc_%": round(100 * d["trunc"] / n, 1),
                              "ci_leak_%": round(100 * d["ci"] / n, 1),
                              "short_ans_%": round(100 * d["short"] / n, 1),
                              "mean_ans_chars": round(d["alen"] / n),
                              "answer_leak_%": (round(100 * d["leak"] / d["leak_denom"], 1) if d["leak_denom"] else None)}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", required=True); ap.add_argument("--eval", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    tr = [json.loads(l) for l in open(a.train)]
    ev = [json.loads(l) for l in open(a.eval)]
    res = {"train": audit(tr, "train"), "eval": audit(ev, "eval")}
    json.dump(res, open(a.out, "w"), indent=2)
    for split in ("train", "eval"):
        r = res[split]
        print(f"\n===== {split.upper()} ({r['total']} rows) | exact-dup-answers={r['exact_dup_answers']} "
              f"dup-pairs={r['exact_dup_pairs']} same-answer-multi-task={r['same_answer_multiple_tasks']} =====")
        print(f"{'task':28s}{'n':>6s}{'trunc%':>7s}{'ci%':>6s}{'short%':>7s}{'leak%':>7s}{'alen':>6s}")
        for t, d in r["per_task"].items():
            print(f"{t:28s}{d['n']:6d}{d['trunc_%']:7}{d['ci_leak_%']:6}{d['short_ans_%']:7}"
                  f"{str(d['answer_leak_%']):>7}{d['mean_ans_chars']:6}")


if __name__ == "__main__":
    raise SystemExit(main())
