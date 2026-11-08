"""Assemble multitask_sft_v8 = v5 base + DB-grounded SFT (9k) + routing CoT + generative CoT.
Exact-dedup on (user,assistant); prepend the system turn to CoT rows for uniformity; shuffle. Usage:
  python assemble_v8.py --dir /tmp/sftaudit --out /tmp/sftaudit/multitask_sft_v8.jsonl
"""
import argparse, json, os, random, collections
random.seed(8)
SYS = "You are BioMate, an agentic bioinformatics assistant."


def rows(path):
    if not os.path.exists(path):
        print(f"  (absent, skipped) {path}"); return []
    out = []
    for l in open(path):
        if l.strip():
            out.append(json.loads(l))
    return out


def key(r):
    m = {x["role"]: x["content"] for x in r["messages"]}
    return (m.get("user", "").strip(), m.get("assistant", "").strip())


def withsys(r):
    if r["messages"] and r["messages"][0]["role"] != "system":
        r["messages"] = [{"role": "system", "content": SYS}] + r["messages"]
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="/tmp/sftaudit")
    ap.add_argument("--out", default="/tmp/sftaudit/multitask_sft_v8.jsonl")
    a = ap.parse_args()
    sources = [("v5", "multitask_sft_v5_norm.jsonl"), ("db_grounded", "db_grounded_seeds.jsonl"),
               ("cot_routing", "cot_routing.jsonl"), ("cot_generative", "cot_distill.jsonl")]
    all_rows, seen, prov = [], set(), collections.Counter()
    for tag, fn in sources:
        rs = rows(os.path.join(a.dir, fn)); added = 0
        for r in rs:
            r = withsys(r); k = key(r)
            if not (k[0] and k[1]) or k in seen:
                continue
            seen.add(k); all_rows.append(r); prov[tag] += 1; added += 1
        print(f"  {tag}: {len(rs)} read, {added} new (dedup)")
    random.shuffle(all_rows)
    with open(a.out, "w") as f:
        for r in all_rows:
            f.write(json.dumps(r) + "\n")
    by_task = collections.Counter(r.get("task", "?") for r in all_rows)
    print(f"\nV8: {len(all_rows)} rows -> {a.out}\n  provenance={dict(prov)}\n  by-task(top)={dict(by_task.most_common(12))}")


if __name__ == "__main__":
    raise SystemExit(main())
