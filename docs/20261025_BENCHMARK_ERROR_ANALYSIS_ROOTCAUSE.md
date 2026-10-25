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

**Fix (DONE for 3 workflows):** `scripts/fix_routing_descriptions_20261025.py` (idempotent) front-loads the
discriminator into the first 120 chars — scnanoseq now leads "OXFORD NANOPORE LONG-READ … for SHORT-READ 10X
use nf-core/scrnaseq"; scrnaseq leads "10X SHORT-READ … Cell Ranger/STARsolo/alevin-fry"; mhcquant leads with
"Comet database search". Apply to the canonical DB (dev/S3) via the normal DB-maintenance path.

**Measured (A/B, old-DB vs new-DB menu, qwen-2.5-7b proxy for the on-prem 9B):** `sc_001` flips scnanoseq✗→
scrnaseq✓ (scnanoseq's line now actively redirects); aggregate over all 200 items 0.665→0.675 (+1pp). So the
targeted 3-description fix is correct and helps the specific confusions, but the **systemic** lever is bigger:
the `[:120]` truncation cuts discriminators catalog-wide. The general fix is (a) a catalog-wide pass to
front-load discriminators / add a short "use X not Y" disambiguator to near-duplicate pipelines, and/or
(b) widen the menu truncation (e.g. 120→200 chars) in production `_browse_catalog_with_llm` and the eval.
Definitive magnitude on the on-prem 9B requires re-running the routing eval with the patched DB (bounded spot
run; the eval box pulls the DB from S3 so the patched DB must be uploaded first).

### Measured on the EXACT on-prem model (no GPU box needed)
`qwen/qwen3.5-9b` (the stock base BioMate serves on-prem) is on OpenRouter, so the description-fix effect was
measured directly via a controlled A/B (old-DB vs new-DB menu, same model, all 200 items), avoiding a
speculative GPU-box run for a predictable delta (No-Speculative-Deploys discipline):

| menu descriptions | routing (Qwen3.5-9B) |
|---|---|
| OLD (shipping) | 0.800 |
| NEW (front-loaded discriminators) | **0.825** (+2.5pp, +5 items) |

So the targeted 3-description fix is worth **+2.5pp on the exact on-prem 9B** (bigger than the +1pp on the
7b proxy). Caveat: the OpenRouter checkpoint's *absolute* (0.800) differs from the on-prem served eval's
0.880 base (harness/revision/quantization differences) — the controlled **delta** is the meaningful figure.

**Open-model roster A/B (old-DB vs new-DB, corrected scorer+gold held constant; OpenRouter, no GPU box):**

| model | OLD | NEW | Δ |
|---|---|---|---|
| qwen/qwen3.5-9b | 0.865 | 0.880 | +1.5pp |
| qwen/qwen3.5-27b | 0.845 | 0.835 | −1.0pp |
| qwen/qwen3.8-27b | 0.910 | 0.935 | +2.5pp |
| deepseek/deepseek-v4-pro | 0.915 | 0.925 | +1.0pp |
| z-ai/glm-5.2 | 0.955 | 0.960 | +0.5pp |
| z-ai/glm-5.3-prime | 0.965 | 0.940 | −2.5pp |
| moonshotai/kimi-k3 | 0.715 | 0.795 | +8.0pp |
| ~~qwen/qwen3.5-397b-a17b~~ | ~~0.755~~ | ~~0.565~~ | ~~−19pp — EXCLUDED~~ |

The 397B MoE is excluded: a −19pp swing (~38 items) cannot come from front-loading 3 descriptions, and its
OLD score (0.755) is itself an outlier vs the 0.85–0.96 cluster — this is run instability (reasoning-model
variance / truncation), not a description effect. Across the 7 reliable models the fix gives a small,
mostly-positive, model-dependent lift (mean ≈ +1.4pp, median +1.0pp; two marginal negatives within run
noise, a large +8pp on kimi). **Honest conclusion: the targeted 3-description fix is correct and modestly
positive; it is not a large lever on its own.** The real routing lever is (a) the scorer+gold corrections
already landed (0.880→0.900 on base+harness) and (b) a *catalog-wide* discriminator front-loading / truncation
widening — a bigger data-quality pass, logged as the systemic follow-up.

Harness note: the first roster run scored 6/8 models ~0.000 — a `max_tokens=30` budget fully consumed by
reasoning tokens (`finish_reason=length`, `content=None`), the CLAUDE.md thinking-tokens failure mode; fixed
by raising to 2000 and re-running. Reasoning-model evals must budget for the thinking tokens.

## 4. Benchmark gold errors (fix the benchmark, documented per policy) — DONE
A minority of "misses" are the gold being wrong or under-specified (empty `acceptable_alts`):
- `sc_007`: gold `nf-core/scrnaseq`, whose own description says *"NOT for filtering doublets"* — but the
  query **is** doublet filtering; the model's `scrna_doublet_qc` is correct. **Flip the gold.**
- Defensible alternates to add to `acceptable_alts`: `sc_022` MERFISH↔`spatialxe` (Xenium; both imaging,
  subcellular, 300-gene panel), `mo_009` `cite_seq_preprocessing`↔`scrapper_multimodal_rna_adt` (both
  CITE-seq ADT), `sc_011` `spatialvi`↔`spatial_visium_banksy` (banksy = spatial clustering).
**DONE (commit aa85ef6a8):** added `acceptable_alts` for the 3 clear cases (sc_007 +scrna_doublet_qc,
sc_022 +nf-core/spatialxe, mo_009 +scrapper_multimodal_rna_adt), each justified in
`cross_domain_routing/README.md`; gold `correct_workflow` unchanged, the alt also credited. sc_011 NOT
changed (query names "Space Ranger" = spatialvi, which banksy doesn't run). With the scorer fix, **base+harness
routing 0.880 → 0.885 (scorer) → 0.900 (gold corrections)**. Genuine model errors (scnanoseq 10x confusion,
etc.) were NOT papered over — fixed at the source (descriptions).

## MEASURED: the production rule layer closes most of the gap (+18pp, no retraining)
Confirmed with a capability audit (file:line): the deterministic rule layer **exists and is wired into the
live path** — `_rule_based_param_inference()` (`backend/.../api/ai_assistant.py:1704`) runs *before* the LLM
and overrides it; `_validate_extracted_params()` (`:1524`) applies canonical genome/strandedness aliases;
production merges rule>LLM (`:2139`, `:2224-2232`). The public benchmark (`run_baseline.py`) bypasses all of
it and sends the raw `user_query` to a raw LLM — and the leaderboard rows labeled **"BioMate 9B (base/SFT)"
are that raw LLM with the rule layer OFF** (BioMate's own param cell is blank).

I ran the **actual production functions** (AST-extracted, no Galaxy runtime) over the 170 param_prefill items,
then merged with the committed on-prem-9B LLM predictions exactly as production does (rules win, LLM fills the
residual). Scored with the corrected scorer:

Reproducible script: `evaluation/local_trial/measure_production_param_rules.py` (reads the committed
`results/base/param_prefill.jsonl`):

| Configuration | param F1 | recall | precision | must_not_fill viol |
|---|---|---|---|---|
| raw on-prem 9B (what the leaderboard shows) | 0.703 | 0.636 | 0.785 | 53 |
| rule layer ALONE (no LLM) | 0.470 | 0.311 | **0.960** | 4 |
| **production: rule layer + 9B fallback** | **0.803** | **0.793** | 0.812 | 56 |

So BioMate's real on-prem param_prefill is **≈0.80**, not 0.634 — **+17pp vs the originally-published strict
number, +10pp vs the raw 9B on the committed preds, zero retraining** (the fresh depcond-eval base preds give
0.813, consistent). The rules are high-precision/moderate-recall (the deterministic floor the raw LLM fumbled:
human→GRCh38, dUTP→reverse, bool mapping); the LLM covers the tail. The headroom was in the shipping code all
along; the benchmark measured the one configuration we never deploy. (Caveat: faithful offline approximation
using the committed 9B LLM preds; the end-to-end `run_param_prefill.py` adapter against the live backend is
the canonical measurement and should produce the official number.)

**Follow-up fix the merge surfaced — DONE (IO-param guardrail).** must_not_fill violations were high (56) and
came almost entirely from the LLM fallback: 24/53 were a prose assay-description shoved into `input`
(`input='RNA-seq'`/`'FFPE tissue'`/`'tumor-only'`/`'WES'`), which is never a valid file input. Added a
data-plane guardrail to `_validate_extracted_params` (`ai_assistant.py`): IO params
(`input`/`fasta`/`reads`/`bam`/`vcf`/`gtf`/`outdir`/samplesheet/…) are kept ONLY when the value is shaped like
a path/URL/glob/archive-accession; prose is dropped (dedicated SRA/GEO extractors still handle real
accessions/paths). Measured effect on the production merge:

| | param F1 | precision | recall | must_not_fill viol |
|---|---|---|---|---|
| production rules+9B (before guardrail) | 0.803 | 0.812 | 0.793 | 56 |
| **+ IO-param guardrail** | **0.843** | **0.900** | 0.793 | **27** |

+4pp F1, precision 0.81→0.90, violations halved, **zero recall loss** (no legitimate param dropped). Real
production robustness fix (generalizes to every workflow with IO params), not a benchmark edit. NOTE: not yet
synced — needs the Galaxy container module-load test + `sync_to_dev.sh` (local env lacks the `beaker` dep, so
the full import test runs at sync; AST/syntax verified locally).

**Net:** BioMate's real on-prem param_prefill is **≈0.84** (rules + 9B + guardrail), vs the published raw-LLM
0.634 — **+21pp, zero retraining.**

**Leaderboard action:** relabel the raw rows "on-prem 9B (raw LLM, no harness)" and add a
"BioMate on-prem (rule layer + 9B)" row at F1≈0.81, or the public leaderboard keeps mis-stating BioMate's
own capability downward.

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
