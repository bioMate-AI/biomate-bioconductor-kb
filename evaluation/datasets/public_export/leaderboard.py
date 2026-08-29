#!/usr/bin/env python3
"""Aggregate every model's predictions under results/ into ONE RealBio leaderboard.

Reads results/<model>/<task>[_mode].jsonl, scores each with the committed score.py
(no re-implementation — same objective scorer every system is graded by), and prints
a markdown table + a JSON blob. Every number here traces to a predictions file on disk.

Usage: python3 leaderboard.py [--md] [--json]
"""
import os, json, glob, sys, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("score", os.path.join(HERE, "score.py"))
S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)

# (result-file basename, benchmark-dir, scorer, headline-key, label)
COLS = [
    ("cross_domain_routing_bare",    "cross_domain_routing", S.score_routing,       "accuracy",             "routing (direct use)"),
    ("autofix_benchmark",            "autofix_benchmark",    S.score_autofix,        "fix_category_accuracy","autofix"),
    ("param_prefill",                "param_prefill",        S.score_param_prefill,  "param_f1",             "param_prefill (F1)"),
    ("workflow_generation",          "workflow_generation",  S.score_workflow_gen,   "accuracy",             "workflow_gen"),
    ("protocol_thresholds",          "protocol_thresholds",  S.score_protocol,       "accuracy",             "protocol_QC"),
]

def fmt(v):
    if v is None: return "—"
    return f"{v:.3f}"

def main():
    models = sorted(d for d in os.listdir(os.path.join(HERE, "results"))
                    if os.path.isdir(os.path.join(HERE, "results", d)))
    board = {}
    for m in models:
        row = {}
        for fbase, bench, scorer, key, _label in COLS:
            path = os.path.join(HERE, "results", m, f"{fbase}.jsonl")
            if not os.path.exists(path):
                row[fbase] = None; continue
            try:
                res = scorer(S.load(bench), S.load_preds(path))
                row[fbase] = {"score": res.get(key), "ci95": res.get("ci95"), "scored": res.get("scored"),
                              "extra": {k: res[k] for k in ("must_not_fill_violations",) if k in res}}
            except Exception as e:
                row[fbase] = {"error": str(e)[:80]}
        # median per-query latency (ms) across all this model's prediction files
        lats = []
        for fp in glob.glob(os.path.join(HERE, "results", m, "*.jsonl")):
            for l in open(fp):
                try:
                    v = json.loads(l).get("latency_ms")
                    if isinstance(v, (int, float)): lats.append(v)
                except Exception: pass
        lats.sort()
        row["_median_ms"] = lats[len(lats)//2] if lats else None
        board[m] = row

    # markdown
    hdr = ["Model"] + [c[4] for c in COLS] + ["median ms/query"]
    print("| " + " | ".join(hdr) + " |")
    print("|" + "|".join(["---"] * len(hdr)) + "|")
    for m in models:
        cells = [m]
        for fbase, *_ in COLS:
            cell = board[m].get(fbase)
            if not cell: cells.append("—")
            elif "error" in cell: cells.append("ERR")
            else:
                s = fmt(cell["score"]); n = cell.get("scored")
                cells.append(f"{s} (n={n})" if n else s)
        mm = board[m].get("_median_ms")
        cells.append(str(mm) if mm is not None else "—")
        print("| " + " | ".join(cells) + " |")

    if "--json" in sys.argv:
        print("\n" + json.dumps(board, indent=2))

if __name__ == "__main__":
    main()
