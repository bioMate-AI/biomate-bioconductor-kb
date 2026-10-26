> ⚠️ **Before citing any leaderboard number, read [LEADERBOARD_CAVEATS.md](LEADERBOARD_CAVEATS.md)** — known data-quality caveats (menu-condition split, empties by cause, raw-LLM-vs-production param rows, do-not-claim SFT wins).

# RealBio Benchmark — run it & submit

Real-world, objectively-scored benchmarks for bioinformatics AI agents. **660 items across 8 tasks**,
one shared open scorer, **no LLM judge**. This repo is the **code + scorer + committed predictions** —
run your system, score it here, open a PR to appear on the board.

> **Just want the data?** → the Hugging Face dataset: [YaoyunZhangHug/realbio_benchmark](https://huggingface.co/datasets/YaoyunZhangHug/realbio_benchmark)
> **Just want the story + leaderboard?** → [biomate.ai/realbio](https://biomate.ai/realbio)
> Full role split: `docs/20260827_REALBIO_THREE_SURFACES_ROLES.md`.

## Quick start
```bash
git clone https://github.com/bioMate-AI/realbio-benchmark
cd realbio-benchmark

# 1. produce predictions for a task — one JSON per line: {"id": "...", "prediction": <answer>}
#    (per-task prediction format is documented at the top of score.py and in each <task>/README.md)

# 2. score them — objective metric, no judge:
python3 score.py cross_domain_routing my_preds.jsonl
```

## Layout
| Path | What |
|---|---|
| `<task>/data.jsonl` | items + ground truth (+ a `difficulty` label on 6 tasks) |
| `<task>/README.md` | that task's prediction format + metric |
| `score.py` | the one objective scorer (all tasks) |
| `results/<model>/<task>.jsonl` | committed predictions for every system on the board |
| `leaderboard.py` | regenerates `leaderboard.{md,csv}` from `results/` via `score.py` |
| `difficulty_breakdown.py` | per-difficulty × per-method table (reuses `score.py`) → `difficulty_breakdown.{md,csv}` |

## Regenerate the board
```bash
python3 leaderboard.py            # -> leaderboard.md + leaderboard.csv  (every cell re-scores from results/)
python3 difficulty_breakdown.py   # -> difficulty_breakdown.md + .csv    (task × difficulty × method)
```

## Submit your system
1. Run every task; write predictions to `results/<your-system>/<task>.jsonl`.
2. `python3 leaderboard.py` to see your row.
3. Open a PR with your `results/<your-system>/` dir. Every number is recomputed by `score.py` from your
   committed predictions — nothing is self-reported.

## The 8 tasks
`cross_domain_routing` (200) · `param_prefill` (170) · `protocol_thresholds` (100) ·
`autofix_benchmark` (100) · `workflow_generation` (40) · `boin_benchmark` (20) ·
`pbpk_benchmark` (15) · `drug_discovery_e2e` (15). Schema + metric per task in each `<task>/README.md`.

## License
CC-BY-4.0. Please cite (see the Hugging Face dataset card for the BibTeX + forthcoming DOI).
