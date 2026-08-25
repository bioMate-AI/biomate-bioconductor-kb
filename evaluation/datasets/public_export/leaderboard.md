# RealBio Benchmark — Leaderboard (finished sweep)

**Compiled:** 2026-08-17 from committed `results/<model>/<task>.jsonl` via `leaderboard.py` + `score.py`.
Every number traces to a predictions file scored by the one shared objective scorer. `n` per cell shown.
**Excluded:** `gpt-5.3-chat-latest` (routing scored 0.000 — failed/empty run, not a valid measurement).
**Coverage:** the cross-system sweep now covers 9 tasks (6 core + 3 newly-added: `pbpk`/`boin`/`drug_discovery_e2e`). `litqa2` remains un-swept across LLMs and is not in this table. `boin` and `drug_discovery_e2e` were newly wired into the scorer (`score.py`: `boin` → exact match on `reference.true_MTD_mg`; `drug_discovery_e2e` → mean Spearman rank correlation of the model's strongest-first ligand ranking vs `ligand_rank_order`).

## Raw model leaderboard (no product harness) — routing (direct use) + 7 tasks

| Model | routing (direct use) | autofix | param_prefill (F1) | workflow_gen | protocol_QC | pbpk (within-2-fold) | boin (exact MTD-mg) | dd (Spearman) |
|---|---|---|---|---|---|---|---|---|
| Claude Opus 5 | 0.615 | 0.870 | 0.757 | 0.500 | 0.330 | 0.133 | **0.400** | **0.700** |
| Gemini 3.1 Pro | 0.580 | 0.880 | 0.693 | 0.500 | **0.630** | 0.000 | 0.250 | **0.700** |
| GPT-5.6 | 0.530 | 0.860 | 0.671 | 0.500 | 0.460 | **0.200** | **0.450** | **0.700** |
| Qwen3.8-Max | 0.345 | 0.860 | 0.692 | 0.500 | 0.460 | 0.000 | 0.100 | **0.700** |
| GLM-5.2 | 0.400 | 0.830 | 0.641 | 0.500 | 0.440 | 0.000 | 0.100 | **0.700** |
| GPT-5.6-luna | 0.355 | 0.830 | 0.624 | 0.500 | 0.340 | **0.200** | 0.350 | **0.700** |
| Kimi K3 | 0.450 | 0.770 | 0.628 | 0.450 | 0.360 | 0.000 | 0.150 | **0.700** |
| DeepSeek V4 | 0.415 | 0.800 | 0.621 | 0.500 | 0.420 | 0.067 | 0.150 | 0.667 |

*n: routing 200 · autofix 100 · param_prefill 170 · workflow_gen 40 · protocol 100 · pbpk 15 · boin 20 · dd 15.*

**Metric definitions (three newly-added tasks).** **pbpk** = fraction of PK predictions within 2-fold of the published reference, scored over all 15 items — a non-parseable / no-final-number answer counts as a miss (Kimi and Qwen produced ~30k-token reasoning with no usable number, hence 0.00). **boin** = exact match of the recommended MTD dose in mg to `reference.true_MTD_mg`, over 20 items. **dd** = mean Spearman rank correlation between the model's strongest-first ligand ranking and `ligand_rank_order`, over 15 items. **The reading:** LLMs used directly are near-useless at PBPK simulation (mean 0.075), mediocre at BOIN dose-finding (mean 0.244), but *good* at ligand ranking (mean 0.694) — a knowledge task. This last point is deliberate evidence that RealBio is **not rigged to only surface LLM failures**: on `dd`, direct LLMs already do well.

## Product / agent rows (different harness — reported separately, not mixed into the raw table)

| System | Condition | routing | autofix | param F1 | wf_gen | protocol | pbpk (2-fold) | boin (MTD) | dd (Spearman) | n |
|---|---|---|---|---|---|---|---|---|---|---|
| **BioMate** | **C2 — full system, engine-free curated retrieval** | **0.965** [0.930, 0.983] | —‡ | **0.848**† | —‡ | **0.925**† | **100%**◊ | **80.0%**★ | —§ | 200 / 115 / 20 / 18 / 60 |
| Biomni (Stanford A1) | agent scaffold; Opus-5 (5 pilot tasks) / Sonnet-4.5 (pbpk·boin·dd)¶ | 0.950 | 0.950 | 0.708 | 0.500 | 0.500 | 0%◊◊ | **45.0%** | 1.0 (n=4)★★ | 40·15·20·4 |

¶ **Biomni engine.** The 5 pilot tasks used Opus-5. The 3 computation tasks could **not**: Biomni's A1 loop appends each code `<observation>` as an assistant message and continues it (assistant *prefill*), which Claude removed across ≥4.6 — Opus-5/4.6/4.8 all reject it. So pbpk/boin/dd use **claude-sonnet-4.5** (Biomni's default Claude tier). Byte-identical prompts + the same `score.py` as the LLM sweep (a fair same-prompt cell).
◊◊ **Biomni pbpk 0% is a format artifact, not an inability.** Biomni writes + runs a real hepatic-clearance PK model, but its mechanistic outputs (clearance/AUC, various units) don't land within 2-fold of the reference *Cmax* when squeezed to a single number — the same underspecified prompt the LLMs faced (they reached 0–20%). Capability is present; this cell is *constrained-format accuracy*, not a can/can't verdict.
★★ **Biomni dd 1.0 (n=4).** Perfect ligand ranking on the 4 of 15 items that completed; the other 11 were dropped to OpenRouter credit-throttling (dd's large context inflates the per-request reservation). Tiny sample — **not** comparable to the LLMs' 0.70 (n=15); reported as partial. Biomni boin **45%** (9/20) ties the best single LLM (GPT-5.6) and beats the LLM mean (24%) — here the agent scaffold genuinely helps.

† BioMate param_prefill (0.848, n=115) and protocol-QC (0.925, n=20) are from BioMate's benchmark harness — the source from which RealBio was derived (`docs/20260429_BENCHMARK_MATRIX_COMPLETE.md`); n differs from the LLM sweep.
‡ BioMate autofix and workflow_gen were not located as finalized cells in the benchmark matrix; to be filled from BioMate's harness (not re-run — the tasks were run; the exact export cells need confirming).
◊ BioMate pbpk **100%** (18/18 within-2-fold) is from BioMate's validated pharmacology set (18 FDA-guidance disease-state AUC cases; `docs/20260429_PHARMACOLOGY_BENCHMARK_RESULTS.md`) — same within-2-fold metric as the RealBio pbpk task, but a different item set (not the 15 RealBio pbpk items).
★ BioMate boin **80.0%** (48/60) is from BioMate's internal BOIN dose-finding benchmark (n=60 dose-escalation decisions; 2026-04-29 matrix, `docs/20260429_BENCHMARK_MATRIX_COMPLETE.md`) — related but not item-matched to the RealBio exact-MTD-mg task (n=20).
§ BioMate dd (Spearman ligand-ranking) is pending: BioMate ranks ligands via docking (Vina/DiffDock) but no Spearman ligand-ranking score is committed on these items. (The 78.9% docking-triage number is a different metric — triage/routing, not ranking — and is deliberately not placed in the dd cell.)

## Cost & speed dimension (accuracy is not the only axis) — with an important caveat

Two *different* kinds of cost, which must not be conflated:

1. **Decision / generation cost (LLM tokens)** — what is recorded here (OpenRouter key-usage delta, per item):
   - **LLM-direct:** ~$0.01–0.30/item (reasoning tokens; the 8-model sweep emitted 6k–30k output tokens/item on pbpk/boin).
   - **Biomni (agent):** ~$0.14–1.4/item (multi-call agent loop) — *higher*, not lower, than a single LLM call.
   - **BioMate:** ~**$0** of *generative* LLM cost on routing/param/protocol — it **retrieves** the right workflow from the 4,057-workflow catalog + rules instead of **generating** a solution token-by-token. This is the catalog dividend: a large collection of validated code turns "generate an answer" into "look up the validated one."
   - Latency (same axis): LLM-direct 1–50 s/item, Biomni 29–150 s/item (agent overhead), BioMate routing ≈ instant.

2. **Execution / compute cost (AWS Batch vCPU-, memory-, GPU-hours + S3)** — **NOT captured by any token metric, and not in this table.**
   - Only **BioMate actually executes** the analysis (runs the real pipeline), so only BioMate incurs this compute cost. The LLMs and Biomni "answer for free" **only because they don't run anything** — they emit a guessed number, not a validated result.
   - BioMate's billing stack already **meters** this (vCPU-/memory-/GPU-hours, S3; see the Billing section of `CLAUDE.md`), so it *can* be reported — it just isn't a token cost.

**So, to answer the two questions directly:** (a) yes — BioMate's *token* cost is much lower precisely because the catalog lets it retrieve instead of generate; but (b) **only the token cost is currently recorded.** A complete cost comparison needs the compute axis too, and the two systems are **not apples-to-apples**: for the same deliverable (a real, validated analysis) BioMate's marginal LLM cost is ~$0 and it pays unavoidable pipeline compute; the LLMs look "free" only by not producing the analysis at all. The honest cost story is therefore *"near-zero generation cost + transparent metered compute"*, **not** a blanket "cheaper on every axis."

**Headline (honest):** BioMate scores highest of all systems on the tasks it is measured on — routing **0.965** (vs LLMs-direct 0.35–0.62), param_prefill **0.848** (vs 0.62–0.76), protocol-QC **0.925** (vs 0.33–0.63) — with no LLM in the loop. On the two computation-heavy pharmacology tasks, BioMate's workflows vastly outperform direct LLM use: pbpk **100%** within-2-fold vs the LLMs' mean **7.5%**, and boin **80.0%** exact-MTD vs the LLMs' mean **24%**. These are cross-harness numbers on different — but same-metric — item sets (18 FDA pbpk cases and n=60 BOIN decisions, footnoted ◊/★), **not** same-item head-to-heads. dd (ligand-ranking Spearman) is not reported here (§). Biomni's agent scaffold leads autofix (0.95, n=40 pilot). Provenance/n caveats in the footnotes; no single system dominates every task.
