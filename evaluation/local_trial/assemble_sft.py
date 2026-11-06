"""Assemble ONE consolidated SFT corpus (v4) from all gathered sources, rebalanced per the committee:
downsample the teacher-distilled QA tasks (replaced by gold QA), add gold QA + Claude-log decomposition +
Latch trajectories. Dedup, provenance-labeled, shuffled. Reports composition. Usage:
  python assemble_sft.py --out multitask_sft_v4.jsonl
"""
import argparse, glob, hashlib, json, os, random, collections
random.seed(41)
P = "/Users/kky/biomate-review/docs/20260912_onprem_llm/data_pool_v2"

# (path, per-task caps dict or None). Caps applied only to that file's tasks.
SOURCES = [
    (f"{P}/multitask_sft_big.jsonl", {"tool_recommendation": 1500, "knowledge_recall": 1500, "scientific_qa": 1500}),
    ("/tmp/qa_gold.jsonl", None),        # 25k gold biomedical QA (replaces teacher QA)
    ("/tmp/claude_decomp.jsonl", None),  # 8.4k real decomposition (user's style)
    ("/tmp/latch_traj.jsonl", None),     # 132 frontier bio-agent solutions
]
CI_LEAK = ("/rlib", "flagged as runnable", "test environment", "synthetic fixture")


def taskof(r): return r.get("task", r.get("task_type", "?"))
def ukey(r):
    m = {x["role"]: x.get("content", "") for x in r.get("messages", [])} if r.get("messages") else {}
    return hashlib.md5((str(m.get("user", r.get("input", "")))[:300] + "||" + str(m.get("assistant", r.get("target", "")))[:200]).encode()).hexdigest()


def leaked(r):
    blob = json.dumps(r).lower()
    return any(k in blob for k in CI_LEAK)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--out", required=True); a = ap.parse_args()
    seen = set(); kept = []; percap = collections.defaultdict(int); dropped_ci = dropped_dup = 0
    for path, caps in SOURCES:
        if not os.path.exists(path):
            print(f"  MISSING {path} (skip)", flush=True); continue
        rows = [json.loads(l) for l in open(path)]
        random.shuffle(rows)
        for r in rows:
            t = taskof(r)
            if caps and t in caps and percap[(path, t)] >= caps[t]:
                continue
            if leaked(r):  # committee: drop CI-harness leakage (log_diagnosis/autofix)
                dropped_ci += 1; continue
            k = ukey(r)
            if k in seen: dropped_dup += 1; continue
            seen.add(k)
            if "source" not in r: r["source"] = os.path.basename(path).replace(".jsonl", "")
            kept.append(r); percap[(path, t)] += 1
    random.shuffle(kept)
    with open(a.out, "w") as fo:
        for r in kept: fo.write(json.dumps(r) + "\n")
    bytask = collections.Counter(taskof(r) for r in kept)
    bysrc = collections.Counter(r.get("source", "?") for r in kept)
    print(f"\nCONSOLIDATED v4: {len(kept)} examples (dropped {dropped_dup} dup, {dropped_ci} CI-leak) -> {a.out}")
    print("by task:"); [print(f"  {t:28s}{n}") for t, n in bytask.most_common()]
    print("by source:"); [print(f"  {s:28s}{n}") for s, n in bysrc.most_common()]


if __name__ == "__main__":
    raise SystemExit(main())
