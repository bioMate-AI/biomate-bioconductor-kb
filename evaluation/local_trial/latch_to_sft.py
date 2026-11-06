"""Convert LatchBio benchmark evals -> SFT training examples (INCLUDED, provenance-labeled — not excluded;
per user policy, benchmark data joins the natural distribution). Each eval: task instruction -> a natural
answer stating the gold values from the grader's ground_truth. source=latch_<bench>_<task> for reporting.
Usage: python latch_to_sft.py --root ~/latch-benchmarks --out latch_sft.jsonl
"""
import argparse, glob, json, os, re

SYS = "You are BioMate, an agentic bioinformatics assistant. Perform the analysis and report the key results."


def find_gt(g):
    if not isinstance(g, dict): return None
    cfg = g.get("config", g)
    for k in ("ground_truth", "ground_truth_labels", "expected", "answer"):
        if k in cfg: return cfg[k]
    return None


def verbalize(gt):
    if isinstance(gt, dict):
        return "Key results: " + "; ".join(f"{k.replace('_',' ')} = {v}" for k, v in gt.items()) + "."
    if isinstance(gt, list):
        return "Answer: " + ", ".join(str(x) for x in gt) + "."
    return f"Answer: {gt}."


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.expanduser("~/latch-benchmarks")); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    n = 0; bysrc = {}
    with open(a.out, "w") as fo:
        for path in glob.glob(os.path.join(a.root, "*", "evals", "**", "*.json"), recursive=True):
            if path.endswith("manifest.json"): continue
            bench = path.split("/latch-benchmarks/")[-1].split("/")[0]
            try: d = json.load(open(path))
            except Exception: continue
            instr = d.get("task") or d.get("prompt") or d.get("question")
            gt = find_gt(d.get("grader") or {})
            if not instr or gt is None: continue
            meta_task = (d.get("metadata") or {}).get("task", "analysis")
            fo.write(json.dumps({"messages": [{"role": "system", "content": SYS},
                                              {"role": "user", "content": str(instr)[:2500]},
                                              {"role": "assistant", "content": verbalize(gt)[:1500]}],
                                 "task": "findings_interpretation",
                                 "source": f"latch_{bench}_{meta_task}"}) + "\n")
            n += 1; bysrc[bench] = bysrc.get(bench, 0) + 1
    print(f"LATCH->SFT DONE: {n} examples {bysrc} -> {a.out}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
