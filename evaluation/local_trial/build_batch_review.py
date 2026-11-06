"""FAST batched LLM data-reviewer — judges MANY instances per long-context call (not one-per-call), so the
whole dataset can be audited in minutes. Per-instance verdict {bioinfo, correct, keep} -> contamination %
+ a CLEAN subset (keep=true). Reusable for any {messages} jsonl. Usage:
  python build_batch_review.py --in recipe_sft.jsonl --out-clean recipe_clean.jsonl --batch 40 --workers 16
"""
import argparse, json, re, time
from concurrent.futures import ThreadPoolExecutor
from committee_sft_audit import call

MODEL = ("google", "gemini-3.8-flash")   # fast + long-context; works headless


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True); ap.add_argument("--out-clean", required=True)
    ap.add_argument("--batch", type=int, default=40); ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--max", type=int, default=0)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.inp) if l.strip()]
    if a.max: rows = rows[:a.max]
    def um(r): return {x["role"]: x["content"] for x in r["messages"]}
    batches = [rows[i:i + a.batch] for i in range(0, len(rows), a.batch)]

    def judge(bi_rows):
        bi, brows = bi_rows
        items = []
        for j, r in enumerate(brows):
            m = um(r)
            items.append(f"[{j}] task={r.get('task')}\nUSER: {m.get('user','')[:500]}\nASSISTANT: {m.get('assistant','')[:500]}")
        prompt = ("You are auditing training data for BioMate, a BIOINFORMATICS/computational-biology assistant "
                  "(RNA-seq, variant calling, genomics, proteomics, single-cell, drug discovery). For EACH numbered "
                  "example below, judge two booleans:\n"
                  "  bio = is it genuinely bioinformatics/computational-biology (NOT clinical epidemiology, "
                  "psychology, tourism, materials science, social science, general medicine)?\n"
                  "  correct = is the assistant answer faithful to the user content (no hallucination/causal overclaim)?\n"
                  "keep = bio AND correct.\n"
                  "Reply ONLY a JSON array, one object per example, in order: "
                  "[{\"i\":0,\"bio\":true,\"correct\":true,\"keep\":true}, ...]\n\n" + "\n\n".join(items))
        # RETRY on empty/parse-fail; a FAILED judge must NOT silently become keep=false (that under-counts).
        verdicts = None
        for attempt in range(4):
            o = call(MODEL[0], MODEL[1], prompt, mx=6000)
            m = re.search(r"\[.*\]", o, re.S)
            if m:
                try:
                    v = json.loads(m.group(0))
                    if isinstance(v, list) and len(v) >= max(1, int(0.6 * len(brows))):  # not truncated
                        verdicts = v; break
                except Exception:
                    pass
            time.sleep(2 * (attempt + 1))
        if verdicts is None:
            return [(r, None, None, None) for r in brows]   # judge FAILED -> unknown, excluded from denominator
        vmap = {v.get("i"): v for v in verdicts if isinstance(v, dict)}
        out = []
        for j, r in enumerate(brows):
            v = vmap.get(j)
            if v is None: out.append((r, None, None, None))          # this item missing from array -> unknown
            else: out.append((r, bool(v.get("keep")), bool(v.get("bio")), bool(v.get("correct")))
                              )
        return out

    results = []
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for i, batch_out in enumerate(ex.map(judge, enumerate(batches))):
            results.extend(batch_out)
            if i % 20 == 0: print(f"  batch {i}/{len(batches)}", flush=True)
    judged = [(r, k, b, c) for r, k, b, c in results if k is not None]   # only successfully-judged count
    failed = len(results) - len(judged)
    kept = [r for r, k, b, c in judged if k]
    n = len(judged)
    bio = sum(1 for _, k, b, c in judged if b); corr = sum(1 for _, k, b, c in judged if c)
    with open(a.out_clean, "w") as f:
        for r in kept: f.write(json.dumps(r) + "\n")
    denom = max(n, 1)
    print(f"BATCH REVIEW: {len(results)} total | judged_ok={n} judge_FAILED={failed} | "
          f"bio={bio} ({bio/denom*100:.1f}%) correct={corr} ({corr/denom*100:.1f}%) "
          f"KEEP={len(kept)} ({len(kept)/denom*100:.1f}% of judged) -> {a.out_clean}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
