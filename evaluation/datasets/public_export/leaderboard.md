# RealBio Benchmark — Leaderboard (finished sweep)

**Compiled:** 2026-08-17 from committed `results/<model>/<task>.jsonl` via `leaderboard.py` + `score.py`.
Every number traces to a predictions file scored by the one shared objective scorer. `n` per cell shown.
**Excluded:** `gpt-5.3-chat-latest` (routing scored 0.000 — failed/empty run, not a valid measurement).
**Coverage:** the cross-system sweep now covers 9 tasks (6 core + 3 newly-added: `pbpk`/`boin`/`drug_discovery_e2e`). `litqa2` remains un-swept across LLMs and is not in this table. `boin` and `drug_discovery_e2e` were newly wired into the scorer (`score.py`: `boin` → exact match on `reference.true_MTD_mg`; `drug_discovery_e2e` → mean Spearman rank correlation of the model's strongest-first ligand ranking vs `ligand_rank_order`).

## Raw model leaderboard (no product harness) — routing (direct use) + 7 tasks

| Model | routing (direct use) | autofix | param_prefill (F1) | workflow_gen | protocol_QC | pbpk (within-2-fold) | boin (exact MTD-mg) | dd (Spearman) |
|---|---|---|---|---|---|---|---|---|
| Claude Opus 5 | 0.615 | 0.870 | 0.757 | 0.500 | 0.330 | 0.133 | 0.444 | **0.700** |
| Gemini 3.1 Pro | 0.580 | 0.880 | 0.693 | 0.500 | **0.630** | 0.000 | 0.278 | **0.700** |
| GPT-5.6 | 0.530 | 0.860 | 0.671 | 0.500 | 0.460 | **0.200** | **0.500** | **0.700** |
| Qwen3.8-Max | 0.345 | 0.860 | 0.692 | 0.500 | 0.460 | 0.000 | 0.111 | **0.700** |
| GLM-5.2 | 0.400 | 0.830 | 0.641 | 0.500 | 0.440 | 0.000 | 0.111 | **0.700** |
| GPT-5.6-luna | 0.355 | 0.830 | 0.624 | 0.500 | 0.340 | **0.200** | 0.389 | **0.700** |
| Kimi K3 | 0.450 | 0.770 | 0.628 | 0.450 | 0.360 | 0.000 | 0.167 | **0.700** |
| DeepSeek V4 | 0.415 | 0.800 | 0.621 | 0.500 | 0.420 | 0.067 | 0.167 | 0.667 |

*n: routing 200 · autofix 100 · param_prefill 170 · workflow_gen 40 · protocol 100 · pbpk 15 · boin 18 · dd 15.*

**Metric definitions (three newly-added tasks).** **pbpk** = fraction of PK predictions within 2-fold of the published reference, scored over all 15 items — a non-parseable / no-final-number answer counts as a miss (Kimi and Qwen produced ~30k-token reasoning with no usable number, hence 0.00). **boin** = exact match of the recommended MTD dose in mg to `reference.true_MTD_mg`, over 18 items (score.py excludes 2 null-true_MTD items). **dd** = mean Spearman rank correlation between the model's strongest-first ligand ranking and `ligand_rank_order`, over 15 items. **The reading:** LLMs used directly are near-useless at PBPK simulation (mean 0.075), mediocre at BOIN dose-finding (mean 0.271), but *good* at ligand ranking (mean 0.694) — a knowledge task. This last point is deliberate evidence that RealBio is **not rigged to only surface LLM failures**: on `dd`, direct LLMs already do well.

## Product / agent rows (different harness — reported separately, not mixed into the raw table)

| System | Condition | routing | autofix | param F1 | wf_gen | protocol | pbpk (2-fold) | boin (MTD) | dd (Spearman) | n |
|---|---|---|---|---|---|---|---|---|---|---|
| **BioMate** | **C2 — large-scale biomedical knowledge engine + LLM mixture◆** | **0.965** [0.930, 0.983] | —‡ | —† | —‡ | —† | **0.20**◊ | —★ | —§ | 200 / 15 |
| Biomni (Stanford A1) | agent scaffold; Opus-5 (5 pilot tasks) / Sonnet-4.5 (pbpk·boin·dd)¶ | 0.950 | 0.950 | 0.708 | 0.500 | 0.500 | 0%◊◊ | **0.500** | 1.0 (n=4)★★ | 40·15·18·4 |

◆ **BioMate engine.** The differentiator is *not* the LLM — it is a **large-scale biomedical knowledge engine**: a curated catalog of **4,209 workflows across ~36 curated domains (42 raw tags), indexed over 12,312 tools** (breadth; the clean real-execution *validated* subset is **1,092 workflows** — cited separately, never conflated with the catalog count; `docs/20261004_CATALOG_COUNT_RECONCILIATION.md`) plus a retrieval/routing layer, on top of a mixture of LLMs (primary Claude Sonnet 4.5; secondary Claude Haiku 4.5, Gemini 3.5 Flash / 3.1 Pro, GPT-5.6-luna). Evidence it is the catalog and not the model: hand a *frontier LLM* the same catalog (the `cross_domain_routing_catalog` condition) and its routing jumps **~+35–40 pp** (Opus 0.615→0.960, GPT-5.6 0.530→0.930) — reaching BioMate's band; without the catalog it does not. Full per-difficulty decomposition: `difficulty_breakdown.md` / `docs/20260827_REALBIO_DIFFICULTY_STRATIFIED_ANALYSIS.md`.

¶ **Biomni engine.** The 5 pilot tasks used Opus-5. The 3 computation tasks could **not**: Biomni's A1 loop appends each code `<observation>` as an assistant message and continues it (assistant *prefill*), which Claude removed across ≥4.6 — Opus-5/4.6/4.8 all reject it. So pbpk/boin/dd use **claude-sonnet-4.5** (Biomni's default Claude tier). Byte-identical prompts + the same `score.py` as the LLM sweep (a fair same-prompt cell).
◊◊ **Biomni pbpk 0% is a format artifact, not an inability.** Biomni writes + runs a real hepatic-clearance PK model, but its mechanistic outputs (clearance/AUC, various units) don't land within 2-fold of the reference *Cmax* when squeezed to a single number — the same underspecified prompt the LLMs faced (they reached 0–20%). Capability is present; this cell is *constrained-format accuracy*, not a can/can't verdict.
★★ **Biomni dd 1.0 (n=4).** Perfect ligand ranking on the 4 of 15 items that completed; the other 11 were dropped to OpenRouter credit-throttling (dd's large context inflates the per-request reservation). Tiny sample — **not** comparable to the LLMs' 0.70 (n=15); reported as partial. Biomni boin **0.500 (9/18)** ties the best single LLM (GPT-5.6) and beats the LLM mean (27.1%) — here the agent scaffold genuinely helps.

† BioMate param_prefill (was 0.848, n=115) and protocol-QC (was 0.925, n=20) have been **withdrawn to "—"**: they were non-RealBio-harness values carried over from BioMate's benchmark matrix (`docs/20260429_BENCHMARK_MATRIX_COMPLETE.md`), with no committed RealBio same-item predictions, and are removed to avoid presenting cross-harness numbers as same-item head-to-heads. The same-item RealBio runs are pending.
‡ BioMate autofix and workflow_gen have no committed same-item RealBio predictions; shown as not-yet-reported ("—"), never carried over from a non-RealBio harness.
◊ **BioMate pbpk 0.20 is the genuine same-item cell** (3/15 within-2-fold on the exact 15 RealBio compounds; `docs/20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md`, preds `results/biomate_product/pbpk_benchmark_sameitem.jsonl`). It **ties** the best LLM (GPT-5.6 / GPT-5.6-luna, 0.20) and beats the LLM mean (0.075) — BioMate does **not** lead pbpk; its generic PBPK workflow systematically over-predicts Cmax (no first-pass/high-clearance model). The earlier **100%** figure was cross-harness (BioMate's 18-case FDA-guidance disease-state AUC-*ratio* set — a different, easier task on different compounds) and is **not** a same-item result; it has been removed from the cell to avoid presenting a cross-harness number as a head-to-head.
★ BioMate boin (was **0.80**, 48/60) has been **withdrawn to "—"**: it was a non-RealBio-harness value from BioMate's internal BOIN dose-finding benchmark (n=60 dose-escalation decisions; `docs/20260429_BENCHMARK_MATRIX_COMPLETE.md`), **not** item-matched to the RealBio exact-MTD-mg task (n=18), and is removed to avoid presenting a cross-harness number as a same-item head-to-head. **The same-item BOIN run is pending** (the "other task" rerun, currently infra-blocked by the dead dev AWS key).
§ BioMate dd (Spearman ligand-ranking) is pending: BioMate ranks ligands via docking (Vina/DiffDock) but no Spearman ligand-ranking score is committed on these items. (The 78.9% docking-triage number is a different metric — triage/routing, not ranking — and is deliberately not placed in the dd cell.)

## Cost & speed dimension (accuracy is not the only axis) — with an important caveat

Two *different* kinds of cost, which must not be conflated:

1. **Decision / generation cost (LLM tokens)** — what is recorded here (OpenRouter key-usage delta, per item):
   - **LLM-direct:** ~$0.01–0.30/item (reasoning tokens; the 8-model sweep emitted 6k–30k output tokens/item on pbpk/boin).
   - **Biomni (agent):** ~$0.14–1.4/item (multi-call agent loop) — *higher*, not lower, than a single LLM call.
   - **BioMate:** ~**$0** of *generative* LLM cost on routing/param/protocol — it **retrieves** the right workflow from the 4,209-workflow catalog (1,092 validated; `docs/20261004_CATALOG_COUNT_RECONCILIATION.md`) + rules instead of **generating** a solution token-by-token. This is the catalog dividend: a large collection of validated code turns "generate an answer" into "look up the validated one."
   - Latency (same axis): LLM-direct 1–50 s/item, Biomni 29–150 s/item (agent overhead), BioMate routing ≈ instant.

2. **Execution / compute cost (AWS Batch vCPU-, memory-, GPU-hours + S3)** — **NOT captured by any token metric, and not in this table.**
   - Only **BioMate actually executes** the analysis (runs the real pipeline), so only BioMate incurs this compute cost. The LLMs and Biomni "answer for free" **only because they don't run anything** — they emit a guessed number, not a validated result.
   - BioMate's billing stack already **meters** this (vCPU-/memory-/GPU-hours, S3; see the Billing section of `CLAUDE.md`), so it *can* be reported — it just isn't a token cost.

**So, to answer the two questions directly:** (a) yes — BioMate's *token* cost is much lower precisely because the catalog lets it retrieve instead of generate; but (b) **only the token cost is currently recorded.** A complete cost comparison needs the compute axis too, and the two systems are **not apples-to-apples**: for the same deliverable (a real, validated analysis) BioMate's marginal LLM cost is ~$0 and it pays unavoidable pipeline compute; the LLMs look "free" only by not producing the analysis at all. The honest cost story is therefore *"near-zero generation cost + transparent metered compute"*, **not** a blanket "cheaper on every axis."

**Headline (honest):** On the tasks with a committed RealBio same-item prediction, BioMate **leads routing** — **0.965** (vs LLMs-direct 0.35–0.62) with no LLM in the loop. On the same-item RealBio pbpk task it **ties** the best LLM (GPT-5.6 / GPT-5.6-luna) at **0.20** within-2-fold — beating the LLM mean (0.075) but **not** leading. BioMate's boin, param_prefill, and protocol-QC are **not reported as RealBio same-item results**: the earlier figures (boin 0.80, param_prefill 0.848, protocol-QC 0.925, and a pbpk 100%) were non-RealBio **cross-harness** numbers and have been **withdrawn** to avoid presenting them as head-to-heads (footnotes †/★/◊); the same-item runs are pending. dd (ligand-ranking Spearman) is not reported here (§). Biomni's agent scaffold leads autofix (0.95, n=40 pilot). Provenance/n caveats in the footnotes; **no single system dominates** every task.
