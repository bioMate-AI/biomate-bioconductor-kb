# RealBio — three surfaces, three distinct jobs (why GitHub + HuggingFace + website)

**Date:** 2026-08-27 · **Owner:** Y. Zhang
**Problem being fixed:** today the HuggingFace dataset card and the GitHub repo README are
effectively the **same file** (`evaluation/datasets/public_export/README.md`), and the website
re-states the same leaderboard. Three surfaces that say the same thing invite the fair question
*"why three?"*. This doc assigns each surface **one job it alone does best**, and defines the
single-source-of-truth flow so nothing is triplicated by accident.

## The single source of truth
Everything derives from the git repo — **`evaluation/datasets/public_export/`**:
`data.jsonl` (items + ground truth + difficulty), `score.py` (the one objective scorer),
`results/<model>/<task>.jsonl` (committed predictions), `leaderboard.py` /
`difficulty_breakdown.py` (regenerators). The three public surfaces are **views** on this, each
optimized for a different consumer — they never hold numbers that aren't regenerable from here.

## The three jobs

| Surface | URL | One job | Consumer | Holds | Does NOT hold |
|---|---|---|---|---|---|
| **GitHub** `realbio-benchmark` | github.com/bioMate-AI/realbio-benchmark | **Run & submit** — the code, the scorer, the committed predictions, "how to score your system + open a PR to appear on the board." | An engineer reproducing or entering the benchmark. | `score.py`, `results/`, `leaderboard.py`, `difficulty_breakdown.py`, per-task READMEs, contribution guide. | Marketing narrative. |
| **HuggingFace** dataset | huggingface.co/datasets/YaoyunZhangHug/realbio_benchmark | **Get the data** — a loadable, versioned, **citable/DOI'd** dataset: `load_dataset(...)`, per-config schema, license, citation. | A researcher who wants the *items* (to evaluate, to analyze, to cite). | The dataset card (schema, splits/configs, license, citation), the data files. | The scorer's internals / how the leaderboard is built (→ points to GitHub). |
| **Website** `biomate.ai/realbio` | biomate.ai/realbio | **Tell the story** — why the benchmark matters, the finding (LLMs know biology, fail execution), the leaderboard as a narrative, difficulty stratification as a figure. | A human browsing (BD, press, a researcher deciding whether to engage). | Narrative, the human-readable leaderboard + difficulty chart, links OUT to GitHub + HF. | Runnable code or raw data (→ links to the other two). |

**One-line each:** GitHub = *run it*; HuggingFace = *get + cite the data*; website = *understand why it matters*.
Each surface **links to the other two** and states its own role at the top, so a visitor never wonders "why is this here and not there."

## Concrete divergence work (removing the duplication)
1. **HuggingFace card** (`public_export/README.md`, keeps the HF YAML frontmatter): make it
   dataset-consumption-first — what each config is, the per-item schema, **a `load_dataset` example
   once the HF configs are confirmed**, license, and a **citation block**. Demote "how to score" to a
   one-line pointer to the GitHub repo. *(Do not ship a `load_dataset` snippet with guessed config
   names — confirm the published HF repo structure first; until then, link to the file layout.)*
2. **GitHub README** (`README_GITHUB.md` → repo-root README on publish): code-first — clone, run
   `score.py`, the `results/` layout, regenerate the board with `leaderboard.py`, add your system via
   PR, and the difficulty tooling. Demote the dataset schema to a pointer to the HF card.
3. **Website**: already narrative; add the difficulty-stratified figure/table (see
   `20260827_REALBIO_DIFFICULTY_STRATIFIED_ANALYSIS.md`) — the one thing neither of the other two
   presents visually — and keep the "Run your own system" CTA linking to GitHub + HF.

## Publish mapping (for the manual push — HF creds are user-gated)
- `public_export/README.md` → the **HuggingFace** dataset card (has the YAML frontmatter HF needs).
- `public_export/README_GITHUB.md` → the **GitHub** repo-root README.
- `reference/claude_design/webpage_design_v2/realbio.html` → the **website** page.
Keeping them as three named files with three roles is what prevents the "same thing three times" drift.
