# RealBio — difficulty-stratified performance (each method × each difficulty × each task)

**Date:** 2026-08-27 · **Owner:** Y. Zhang
**Tool:** `evaluation/datasets/public_export/difficulty_breakdown.py` (reuses the official
`score.py` scorers on difficulty-subsetted ground truth — no metric reimplemented).
**Outputs:** `…/difficulty_breakdown.md` (tables) + `…/difficulty_breakdown.csv` (long format).

## Why this exists
The headline leaderboard reports one number per task. But every RealBio item that carries a
difficulty label lets us ask the sharper question: **where exactly do the systems break?** This
is the per-difficulty decomposition for the 6 tasks that ship a per-sample difficulty label.

Difficulty labels are on the ground-truth records (`data.jsonl`), joined to predictions by `id`:

| Task | field | buckets (n) |
|---|---|---|
| cross_domain_routing | `difficulty` | direct 125 / indirect 36 / adversarial 39 |
| param_prefill | `difficulty` | easy 61 / medium 72 / hard 37 |
| workflow_generation | `difficulty` | easy 6 / medium 16 / hard 18 |
| autofix_benchmark | `fix_difficulty` | easy 54 / medium 40 / hard 6 |
| pbpk_benchmark | `difficulty` | easy 3 / medium 7 / hard 5 |
| boin_benchmark | `difficulty` | easy 4 / medium 11 / hard 5 |

*(protocol_thresholds, drug_discovery_e2e, accession_routing, litqa2 carry no difficulty label —
a derived scheme is future work; see §5.)*

## Headline findings

### 1. Routing — BioMate is difficulty-flat; bare LLMs degrade
| difficulty | Opus 5 (bare) | GPT-5.6 (bare) | DeepSeek V4 (bare) | **BioMate** |
|---|---|---|---|---|
| direct (125) | 0.616 | 0.552 | 0.448 | **0.968** |
| indirect (36) | 0.611 | 0.472 | 0.361 | **0.944** |
| adversarial (39) | 0.615 | 0.513 | 0.359 | **0.974** |

BioMate holds ~0.96 across *all* difficulties — it does not wobble on adversarial phrasings, while
weaker bare LLMs lose ~9pp direct→adversarial. This is the robustness a production router needs.

### 2. The knowledge engine is the mechanism — bare vs. catalog
Hand the **same** LLM BioMate's curated catalog (`_catalog` variant) and routing jumps uniformly:

| model | bare (ALL) | +catalog (ALL) | lift |
|---|---|---|---|
| Claude Opus 5 | 0.615 | 0.960 | **+34.5pp** |
| GPT-5.6 | 0.530 | 0.930 | **+40.0pp** |
| Gemini 3.1 Pro | 0.580 | 0.950 | **+37.0pp** |
| DeepSeek V4 | 0.415 | 0.800 | **+38.5pp** |

The lift holds on adversarial items too (Opus 0.615→0.949). **This is the empirical proof that
BioMate's edge is not a bigger model — it is the large-scale biomedical knowledge engine
(indexed tools/workflows catalog + routing).** A frontier LLM with the catalog reaches BioMate's
band; without it, it does not. This is exactly the differentiator to state on the pages (see the
config note in the surfaces plan).

### 3. Difficulty labels behave as designed on the big tasks
- **param_prefill** decays monotonically: Opus 0.836 (easy) → 0.745 (med) → 0.677 (hard); every
  model shows the same gradient — a clean, well-calibrated difficulty axis.
- **workflow_generation** has a cliff: easy **1.0** → medium **0.81** → hard **0.056** (≈1/18) for
  *every* model. The "hard" partition (non-obvious intent→category) is essentially unsolved by
  direct LLMs — the single most dramatic difficulty effect in the benchmark.
- **autofix** is high everywhere (0.77–0.88 overall); mild non-monotonicity at hard is small-n noise.

### 4. Execution tasks fail across the board — BioMate included, honestly
- **pbpk** within-2-fold: LLM field mostly 0.0; best LLM GPT-5.6 **0.20**; **BioMate same-item
  0.20** (ties GPT-5.6, systematic Cmax over-prediction — see `20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md`).
  BioMate does **not** lead pbpk on the same items — the leaderboard's cross-harness 1.00 must be
  corrected (§ surfaces plan / honesty).
- **boin** exact-MTD: mixed; Biomni A1 and GPT-5.6 lead at ~0.50.

## Honesty caveats (must travel with any published version)
- **Small-n buckets:** pbpk (3/7/5), boin (4/11/5), workflow_gen easy (6), autofix hard (6). Per-bucket
  numbers have very wide 95% CIs — read as directional, not precise. Do **not** headline a single
  small-bucket cell.
- **boin looks inverted** (hard 1.0 > easy 0.0). With n=4 easy this is almost certainly a label-semantics
  / small-n artifact, not a real "LLMs are better at hard BOIN." Flagged, not featured.
- **Biomni** ran a 40-item routing subset (not difficulty-stratified) and full pbpk/boin; its per-bucket
  cells are small-n. dd dropped to n=4 on API 402s — excluded here.
- **BioMate** is item-matched only where a committed same-item file exists (routing `c2ir` n=200,
  pbpk same-item n=15). boin/dd BioMate same-item are **pending** a rerun (currently infra-blocked by
  the dead dev AWS key).

## §5. Follow-ups
- Derive a difficulty scheme for the 4 label-less tasks (protocol: naïve≠correct = trap→hard;
  dd: ligand-count/Kd-spread; accession: repository/modality rarity).
- boin same-item BioMate run (the "other task" rerun) once dev Batch is restored.
- Optional bar-chart figure per task (bare vs catalog vs BioMate across difficulty) for the website.
