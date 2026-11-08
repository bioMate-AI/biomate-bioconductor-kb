"""Export flat, browsable per-task files (every instance of each task) + a per-task DEFECT SCAN so the
data can be scrutinized task-by-task. One markdown file per task under data_review/, plus an index and a
defects report. Usage:
  python build_pertask_export.py --sft sft_train.jsonl --outdir <docs>/data_review
"""
import argparse, json, os, re, collections


def msgs(r):
    return {m["role"]: m["content"] for m in r.get("messages", [])}


def clip(s, n=1200):
    s = str(s or "")
    return s if len(s) <= n else s[:n] + " …[truncated]"


# defect probes applied per instance
PROBES = {
    "html_tag": lambda u, a: bool(re.search(r"<(img|div|span|table|br|p)\b|</\w+>", a)),
    "citation_cruft": lambda u, a: bool(re.search(r"\b(REF:|page ?no|edition|et al\.|doi:|©|PMID)\b", a, re.I)),
    "url_in_answer": lambda u, a: "http://" in a or "https://" in a,
    "very_short(<8)": lambda u, a: len(a.strip()) < 8,
    "very_long(>1500)": lambda u, a: len(a) > 1500,
    "answer_echoes_letter_only": lambda u, a: bool(re.fullmatch(r"[A-E][).]", a.strip())),
    "think_leak": lambda u, a: "<think>" in a,
    "assistant_asks_question": lambda u, a: a.strip().endswith("?"),
    "non_ascii_heavy": lambda u, a: sum(ord(c) > 127 for c in a) > max(5, 0.1 * len(a)),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", required=True); ap.add_argument("--outdir", required=True)
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    rows = [json.loads(l) for l in open(a.sft) if l.strip()]
    by = collections.defaultdict(list)
    for r in rows:
        by[r.get("task", "?")].append(r)
    index = ["# Per-task browsable data (train)\n",
             "One file per task with EVERY instance. Defect counts from the scan (see `_DEFECTS.md`).\n",
             "| task | instances | file |", "|---|---|---|"]
    defect_report = ["# Per-task defect scan (train)\n",
                     "Fraction of each task's instances tripping each probe. High = systematic data-quality issue.\n"]
    for t, rs in sorted(by.items(), key=lambda x: -len(x[1])):
        fn = f"train_{t}.md"
        with open(os.path.join(a.outdir, fn), "w") as f:
            f.write(f"# TRAIN task: {t}  ({len(rs):,} instances)\n\n")
            for i, r in enumerate(rs):
                m = msgs(r)
                f.write(f"## [{i}] source={r.get('source','?')}\n\n"
                        f"**USER:** {clip(m.get('user',''))}\n\n"
                        f"**ASSISTANT:** {clip(m.get('assistant',''))}\n\n---\n\n")
        index.append(f"| {t} | {len(rs):,} | `{fn}` |")
        # defect scan
        counts = collections.Counter()
        for r in rs:
            m = msgs(r); u, aa = m.get("user", ""), m.get("assistant", "")
            for name, fn2 in PROBES.items():
                try:
                    if fn2(u, aa):
                        counts[name] += 1
                except Exception:
                    pass
        line = f"\n### {t} ({len(rs):,})\n"
        for name in PROBES:
            c = counts[name]
            if c:
                line += f"- {name}: {c} ({c/len(rs)*100:.1f}%)\n"
        defect_report.append(line if "\n-" in line else line + "- (clean)\n")
    open(os.path.join(a.outdir, "_INDEX.md"), "w").write("\n".join(index))
    open(os.path.join(a.outdir, "_DEFECTS.md"), "w").write("\n".join(defect_report))
    print(f"exported {len(by)} per-task files -> {a.outdir}")
    print("DEFECTS summary:")
    print("\n".join(defect_report[2:]))


if __name__ == "__main__":
    raise SystemExit(main())
