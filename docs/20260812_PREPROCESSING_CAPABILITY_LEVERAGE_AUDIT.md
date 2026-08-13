# Is BioMate's preprocessing/cleaning capability fully leveraged? — audit

Date: 2026-08-12. Prompted by "biomate has so many tools — see if the current ability is
fully leveraged," in the context that data cleaning/preprocessing is the emphasis. Queried the
full local `galaxy_ai_tools.db` (273 MB, 4057 workflows, 12,297 tools; pulled today, full not
stub). Verdict: **capability is real and large, but under-leveraged on the three axes that
matter — enrichment, execution-validation, and QC-verification.**

## Inventory — STRONG (BioMate does not lack tools)

- Preprocessing/cleaning tools: **1,184** — normalize 223, quality 418, filter 573, batch 87,
  outlier 45, impute 26.
- Batch-correction methods present: limma 27, sva 16, harmony 5, scran 4, ComBat 3, mnn 3,
  RUVseq 2. (All the standard bulk + sc batch tools.)
- Cleaning/preprocessing **workflows: 441**.
- Batch tools ARE orchestrated into workflows (not just catalog): limma 140, sva 58, ComBat
  11, harmony 6.
- Chat routing searches BOTH tools (`/api/tool_search`, semantic) and workflows.

→ The raw material for a first-class "clean + verify" stage already exists.

## Leverage gaps — this is where "not fully leveraged" bites

**1. Enrichment: ~39% of cleaning TOOLS are usable by the AI.**
- Preprocessing tools with `scientific_context_v2`: **460 / 1,184 (39%)** → 61% are "dark" —
  the AI can't reason well about them, so they rarely route/generate correctly.
- (Cleaning *workflows* are better: 393/441 = 89% have `annotation_v2`.)

**2. Execution-validation: over half the cleaning workflows are broken-or-unknown.**
Real-exec status of the 441 cleaning workflows:
- ok / ok_warnings: **147 (33%)** ← actually verified runnable
- exec_error: **90 (20%)** ← FAIL when run
- never tested (null): **154 (35%)**
- fixture_failed 31, runnable_assumed 15, timeout 2
→ Only ~1/3 of the cleaning workflows are known-good; ~1/5 error out; ~1/3 never tested. A
user asking to "normalize / remove batch / QC" can easily hit a broken or unproven workflow.
(Whole-DB mirror: 4057 wf → 27% ok/ok_warnings, 20% exec_error, 42% never tested.)

**3. QC-verification: the "did the cleaning work?" layer is almost entirely absent.**
- Cleaning workflows with `qc_steps`: **94 / 441 (21%)**. Whole DB: 430 / 4057 (**11%**).
→ 79% of cleaning workflows have NO QC step, and none verify the harder question we care
about — did normalization flatten signal, did batch correction over-correct, is the sample
an outlier or a real rare population, is the design confounded. The tools to build these
checks exist (223 normalize, 87 batch, the LISI/kBET-style metrics); the verification layer
is just not assembled.

## Conclusion — the moat is leverage + QC, not tool count

BioMate does **not** need more preprocessing tools. To leverage what it has:
1. **Enrich the 61% dark cleaning tools** (`scientific_context_v2`) so the AI can wield them.
2. **Validate/repair the ~55% broken-or-untested cleaning workflows** (90 exec_error + 154
   never-tested) so "clean my data" reliably runs.
3. **Assemble the QC-verification layer** (missing from 79% of cleaning workflows) — the
   generalization of the alignment-QC gate (docs/20260811_ALIGNMENT_QC_FEASIBILITY.md) from
   "batch over-correction" to "is my whole preprocessing trustworthy?"

This closes the loop with the whole thread: the differentiation is not exotic methods or tool
breadth — it's making the existing cleaning capability **reliably runnable and self-verifying**,
which is exactly BioMate's closed-loop-QC lane.

### Caveats
- Numbers from a today-pulled copy of the dev DB; keyword-based category counts (LIKE) so ±
  some boundary error, but the ratios (39% enriched, 33% validated, 21% QC'd) are directionally
  solid. Verify on dev before quoting externally. [[feedback_overclaiming_conclusions]]

## Leverage proof-point — "clean + prove it" on the market's #1 task (built + verified)

`scripts/clean_and_verify_qc_proofpoint.py` — bulk expression normalize → **real ComBat**
(`combat.pycombat`) → outlier flag → **QC VERDICT**. Demonstrates the missing verification
layer on the exact task the RedNote tutorial calls "最关键 / 很多新手翻车," generalizing the
single-cell alignment-QC gate (Gate-1/2) to bulk.

| case | condition sep (biology) | batch sep (technical) | outliers | QC verdict |
|---|---|---|---|---|
| CLEAN (batch ⊥ condition) | 0.247 → **0.472** (kept) | 0.578 → −0.031 (removed) | 0 | **TRUSTED** |
| CONFOUNDED (batch ~ condition) | 0.627 → **0.016** (ERASED) | 0.693 → −0.008 (removed) | 4 | **OVER-CORRECTED** |

The confounded ComBat silently erased disease-vs-normal (0.63→0.02) while "successfully"
removing batch — a passing grade by any batch-mixing check, a GIGO disaster downstream. The
verdict (batch_removed AND biology_kept) catches it; naive "run ComBat" does not.

**What this proves for the leverage thesis:** the differentiator isn't a new tool — it reuses
an EXISTING batch tool (ComBat, 1 of BioMate's 87) and bolts on the verification layer that's
absent from 79% of cleaning workflows. Same verdict logic works bulk (here) and single-cell
(Gate-2), so it's one reusable QC gate across the whole preprocessing stage.

**Caveats:** local feasibility (controlled sim + real ComBat, known ground truth) — NOT yet a
BioMate Batch subworkflow. Productization = wrap normalize→ComBat→outlier→verdict as a runnable
workflow (the tools exist); then validate on real GEO/TCGA batch-labeled data.
