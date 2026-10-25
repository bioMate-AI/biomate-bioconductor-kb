# Benchmark error analysis — "we did something wrong" (we did; it's fixable)

**Date:** 2026-10-25 · Prompted by: *"dig into errors met in the benchmarks … there must be something we
did wrong."* There was. The scores were suppressed by **our eval harness and scorer**, not a model ceiling.
Item-level analysis of the base+harness predictions (`eval/spot_harness_sftv3real_20261025_182648/results/base/`).

## TL;DR — three systemic errors, all ours, all fixable without retraining
| Root cause | Where | Effect (base+harness, no retrain) | Status |
|---|---|---|---|
| Scorer too strict (string identity, not semantic) | `score.py` | param F1 0.634→**0.690**, routing 0.880→**0.885** | **FIXED this commit** |
| Rule layer not wired into eval | harness path | param F1 0.690→**0.737** (organism→genome) | documented, next |
| Workflow descriptions mislead/miss | `galaxy_ai_tools.db` | ≥3 routing misses; also hurts **production** routing | documented, next |

## 1. Scorer measured string identity, not semantic correctness (FIXED)
The model got these RIGHT; the scorer marked them WRONG:
- **routing** `dd_008`: pred `scaffold_hopping` vs gold `Scaffold Hopping` — same workflow, failed only on
  `_`≡space. (`norm()` collapsed whitespace but not underscores.)
- **param** (73 "value-diff" slots): `hg38`≡`GRCh38`, `CE11`≡`WBcel235` (genome assembly synonyms);
  `disabled`≡`False`, `enabled`≡`True` (boolean synonyms); `"16S V3-V4"`⊇`V3-V4` (region containment).
  All semantically correct, all scored as misses by exact string match.

**Fix (committed):** `score.py` now has `norm_wf` (underscore≡space for workflow names) and `val_eq`
(canonical genome/bool aliases + region containment) used by `score_routing` and `score_param_prefill`.
This is a scorer-accuracy fix — it lifts **every** system uniformly (Opus param F1 0.757→0.805, GPT-5.6
0.671→0.716, BioMate-9B-base 0.664→0.703), not a BioMate-specific credit. `leaderboard.csv` regenerated.

## 2. The eval tests the bare LLM, NOT BioMate's rule layer (biggest free lever)
27 param items returned `{}` and 49 genome slots were dropped because the base model couldn't infer the
assembly from the organism (query "human lung adenocarcinoma" → it did not emit `GRCh38`). But
**organism→genome is a deterministic rule in BioMate's own stated architecture** (CLAUDE.md: "rules handle …
canonical alias normalization (human → GRCh38), negations, boolean flags"). The eval harness runs the raw
model without that layer, so it measures a system BioMate does not actually ship.
- Wiring the organism→genome rule recovers **19 true-positive genome slots** the bare model dropped.
- Combined with the scorer fix: param F1 **0.634 → 0.737** (+10.3pp), recall 0.511 → 0.643 — **zero retraining.**

**Fix (next):** inject BioMate's rule-based extraction/normalization between the model output and scoring in
the eval harness (or confirm the production param-prefill path already applies it and eval that path). The
rules exist; they are deterministic, zero-cost, and testable. This is the single highest-leverage change.

## 3. Workflow descriptions mislead the router — hurts the benchmark AND production
The routing catalog is built from the real `description[:120]` in `galaxy_ai_tools.db`, exactly as
production `UnifiedWorkflowSearch._browse_catalog_with_llm`. Several are wrong enough to mis-route:
- **`nf-core/scnanoseq`** (the Nanopore long-read single-cell pipeline) opens with *"…for **10X Genomics**
  single-cell/nuclei RNA-seq…"* — the discriminator "nanopore/long-read" is past char 120. So queries
  *"10x Genomics … Cell Ranger / STARsolo / alevin-fry"* (sc_001, sc_008, sc2_005) lexically match scnanoseq
  over the correct `scrnaseq`. **This mis-routes in production too.**
- **`scrna_doublet_qc`**: no description (name-only in the menu).
- **`nf-core/mhcquant`** description omits "Comet / database search" → `prot_010` ("Comet DB search on
  eluted MHC peptides") routed to `epitopeprediction`.

**Fix (next):** backfill/repair descriptions so the first 120 chars carry the discriminator —
scnanoseq → lead with "NANOPORE long-read single-cell (10X libraries sequenced on ONT)"; scrnaseq → lead
with "10X SHORT-READ single-cell (Cell Ranger / STARsolo / alevin-fry)"; mhcquant → add "Comet database
search". Re-run routing to measure (expect the 3 scnanoseq misses + prot_010 to flip). Generalizable product
improvement, not a benchmark edit.

## 4. Benchmark gold errors (fix the benchmark, documented per policy)
A minority of "misses" are the gold being wrong or under-specified (empty `acceptable_alts`):
- `sc_007`: gold `nf-core/scrnaseq`, whose own description says *"NOT for filtering doublets"* — but the
  query **is** doublet filtering; the model's `scrna_doublet_qc` is correct. **Flip the gold.**
- Defensible alternates to add to `acceptable_alts`: `sc_022` MERFISH↔`spatialxe` (Xenium; both imaging,
  subcellular, 300-gene panel), `mo_009` `cite_seq_preprocessing`↔`scrapper_multimodal_rna_adt` (both
  CITE-seq ADT), `sc_011` `spatialvi`↔`spatial_visium_banksy` (banksy = spatial clustering).
These are ~4–6 items; crediting them (with the scorer fix) puts base routing ≈0.92. Each must be justified in
the data README, never silently baked in.

## What this means for the SFT result
The SFT regression verdict (`docs/20261025_DEPCOND_SFT_EVAL_VERDICT.md`) stands — SFT still hurt — but the
diagnosis sharpens: the real headroom was **never in the model weights**. It was in (1) scoring correctly,
(2) wiring the rule layer the system already specifies, and (3) workflow-description quality. All three are
deterministic/cheap and improve **production**, not just the score. This is the KB-dividend thesis made
actionable: fix the knowledge/harness layer, leave the base model alone.

## Prioritized next actions
1. **DONE** — scorer semantic normalization (`score.py`), leaderboard regenerated.
2. Wire BioMate's rule layer (organism→genome, strandedness, booleans, unit conversions) into the
   param-prefill eval path; re-score. Measured headroom: param F1 → ~0.737. *(no GPU)*
3. Repair the misleading/missing workflow descriptions in `galaxy_ai_tools.db`; re-run routing. *(1 eval box)*
4. Correct the gold errors + add justified `acceptable_alts`; document each in the data README.
5. Re-run the full roster with the corrected harness+scorer before publishing any leaderboard.
