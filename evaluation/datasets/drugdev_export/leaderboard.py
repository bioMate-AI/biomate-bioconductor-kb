#!/usr/bin/env python3
"""Build the DrugDev-Bench leaderboard from committed predictions.

HONEST SCOPE (read before citing any number):
  * The DrugDev suite has 20 task groups. Only THREE carry an adequately-powered,
    objectively-scored accuracy column today — PBPK (n=15), BOIN (n=20), and
    drug_discovery_e2e (n=15) — and every model's predictions for them are committed
    under ../public_export/results/<model>/<task>.jsonl. This script scores those,
    reusing the SAME objective score.py every RealBio system is graded by (no
    re-implementation, no hand values).
  * The remaining 17 task groups are DECISION-PROBES with n=2..10 items each
    (74 items total). Per the project rule against tiny-dataset LLM scoring, an
    n=2 task cannot carry a credible per-task accuracy, so they are NOT emitted as
    leaderboard columns. They must first be POOLED into adequate-n capability
    categories (PK/dose, med-chem/structure, synthesis) before a sweep is scored.
    See docs/20261024_DRUGDEV_LEADERBOARD_HONEST_SCOPE.md.

Every cell traces to a predictions file on disk; blank = that model has no committed
predictions for that task (not-yet-reported, never carried forward).

Usage: python3 leaderboard.py            # writes leaderboard.csv + leaderboard.md
       python3 leaderboard.py --stdout    # print, do not write
"""
import os, sys, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
PUB = os.path.normpath(os.path.join(HERE, "..", "public_export"))
RESULTS = os.path.join(PUB, "results")
spec = importlib.util.spec_from_file_location("score", os.path.join(PUB, "score.py"))
S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)

# CSV column -> (benchmark dir under public_export, scorer, headline key, n)
TASKS = {
    "pbpk_2fold":   ("pbpk_benchmark",     S.score_pbpk,       "within_2fold",       15),
    "boin_mtd":     ("boin_benchmark",     S.score_boin,       "accuracy",           20),
    "dd_spearman":  ("drug_discovery_e2e", S.score_drug_disc,  "mean_spearman_rank", 15),
}
COLS = list(TASKS.keys())

# display name -> results-dir basename (predictions live in public_export/results)
MODELS = [
    ("Claude Opus 5",   "anthropic_claude-opus-5"),
    ("Gemini 3.1 Pro",  "google_gemini-3.1-pro-preview"),
    ("GPT-5.6",         "openai_gpt-5.6"),
    ("GPT-5.6-luna",    "openai_gpt-5.6-luna"),
    ("Qwen3.8-Max",     "qwen_qwen3.8-max"),
    ("Qwen3.8-27B",     "qwen_qwen3.8-27b"),
    ("GLM-5.2",         "z-ai_glm-5.2"),
    ("DeepSeek V4-pro", "deepseek_deepseek-v4-pro"),
    ("Kimi K3",         "moonshotai_kimi-k3"),
    ("BioMate 9B (base)", "base"),
    ("BioMate 9B (SFT)",  "sft"),
    ("Biomni (A1 scaffold)", "biomni_ec2"),
]


def score_cell(col, base):
    bench, scorer, key, _n = TASKS[col]
    path = os.path.join(RESULTS, base, f"{bench}.jsonl")
    if not os.path.exists(path):
        return None
    try:
        res = scorer(S.load(bench), S.load_preds(path))
        v = res.get(key)
        return None if v is None else round(v, 3)
    except Exception as e:
        return f"ERR:{str(e)[:40]}"


def build():
    rows = ["model," + ",".join(COLS)]
    board = {}
    for name, base in MODELS:
        cells = [score_cell(c, base) for c in COLS]
        board[name] = cells
        rows.append(name + "," + ",".join("" if v is None else str(v) for v in cells))
    return rows, board


def md(board):
    hdr = ["Model"] + [f"{c} (n={TASKS[c][3]})" for c in COLS]
    out = ["| " + " | ".join(hdr) + " |", "|" + "|".join(["---"] * len(hdr)) + "|"]
    for name, _ in MODELS:
        cells = board[name]
        out.append("| " + name + " | " + " | ".join("—" if v is None else str(v) for v in cells) + " |")
    return "\n".join(out)


def main():
    rows, board = build()
    csv = "\n".join(rows) + "\n"
    table = md(board)
    if "--stdout" in sys.argv:
        print(csv); print(); print(table); return
    open(os.path.join(HERE, "leaderboard.csv"), "w").write(csv)
    open(os.path.join(HERE, "leaderboard.md"), "w").write(
        "# DrugDev-Bench leaderboard (scored tasks)\n\n"
        "Only the three adequately-powered, objectively-scored tasks are shown. "
        "The 17 decision-probe tasks (n=2..10) are not per-task-scored — see "
        "`docs/20261024_DRUGDEV_LEADERBOARD_HONEST_SCOPE.md`.\n\n" + table + "\n")
    print("wrote leaderboard.csv + leaderboard.md")
    print(table)


if __name__ == "__main__":
    main()
