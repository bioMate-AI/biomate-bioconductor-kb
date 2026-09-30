"""FAST batched LLM data-reviewer — judges MANY instances per long-context call (not one-per-call), so the
whole dataset can be audited in minutes. Per-instance verdict {bioinfo, correct, keep} -> contamination %
+ a CLEAN subset (keep=true). Reusable for any {messages} jsonl. Usage:
  python build_batch_review.py --in recipe_sft.jsonl --out-clean recipe_clean.jsonl --batch 40 --workers 16
"""
import argparse, json, re
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
        o = call(MODEL[0], MODEL[1], prompt, mx=4000)
        m = re.search(r"\[.*\]", o, re.S)
        verdicts = []
        if m:
            try: verdicts = json.loads(m.group(0))
            except Exception: verdicts = []
        vmap = {v.get("i"): v for v in verdicts if isinstance(v, dict)}
        out = []
        for j, r in enumerate(brows):
            v = vmap.get(j, {})
            out.append((r, bool(v.get("keep")), bool(v.get("bio")), bool(v.get("correct"))))
        return out

    results = []
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for i, batch_out in enumerate(ex.map(judge, enumerate(batches))):
            results.extend(batch_out)
            if i % 20 == 0: print(f"  batch {i}/{len(batches)}", flush=True)
    kept = [r for r, k, b, c in results if k]
    bio = sum(1 for _, k, b, c in results if b); corr = sum(1 for _, k, b, c in results if c)
    n = len(results)
    with open(a.out_clean, "w") as f:
        for r in kept: f.write(json.dumps(r) + "\n")
    print(f"BATCH REVIEW: {n} judged | bio={bio} ({bio/n*100:.1f}%) correct={corr} ({corr/n*100:.1f}%) "
          f"KEEP={len(kept)} ({len(kept)/n*100:.1f}%) -> {a.out_clean}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
