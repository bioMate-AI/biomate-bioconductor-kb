# Two uniform-column artifacts diagnosed (workflow_gen 0.500, dd_spearman 0.70)

**2026-10-27.** The 2026-10-27 committee (gemini-3.1-pro, gpt-6.1-sol-pro) independently flagged two columns
whose values are near-identical across every model from 7B to frontier — the classic signature of a broken
scorer or ill-posed prompt, not a capability result. Both are now root-caused. Neither is data leakage (the
committee's guess for dd); both are measurement bugs on our side.

## 1. `workflow_generation` ≈ 0.500 for every model — partition-B prompt/scoring mismatch
- The task has 40 items: **partition A (n=20)** scored on exact `expected_category`; **partition B (n=20)**
  scored on key-tool recall (≥50% of `key_tools`).
- Per-partition breakdown (base, Opus-5, Gemini-3.1): **A = 20/20 for all; B = 0/20 for all.**
- Cause: `run_baseline.py` prompts *every* item with "Select the single analysis CATEGORY…" (it only knows
  `expected_category`). Partition-B items have no `expected_category`; the model returns a category string
  (e.g. `rnaseq`), which is scored against a tool list (`["STAR","ribotricer","xtail","DESeq2","samtools"]`)
  → 0 by construction. **Partition B was never actually asked for tools.**
- Proper fix (not a workaround): report wf_gen as two sub-tasks — **A (category selection, n=20)**, already
  measured ≈1.0 for capable models; **B (key-tool enumeration, n=20)**, re-run with a tool-listing prompt it
  was never given. The composite "0.500" is retired.

## 2. `dd_spearman` = 0.70 for almost every model — length-3 rank lists, NOT leakage
- Every one of the 15 `drug_discovery_e2e` items has a gold `ligand_rank_order` of **length 3**.
- Spearman ρ on 3 items is quantized to **{1.0, 0.5, −0.5, −1.0}** (d² ∈ {0,2,6,8}).
- Per-item ρ is **identical** for Opus-5 and the on-prem base model: twelve items at 1.0, and the **same three
  items** (`sys_005`, `sys_009`, `sys_012`) at −0.5. Mean = (12·1.0 + 3·(−0.5))/15 = **0.70 exactly.**
- Cause: (a) a 3-element ranking is a 4-valued, low-resolution metric that cannot discriminate models; (b) the
  uniformity is a **shared-hard-item** effect — all models mis-rank the same 3 systems, a real but coarse
  signal — not leakage and not a per-model capability spread.
- Proper fix: report dd as a **low-resolution probe** (state the quantization + the 3 shared-hard items as the
  only signal), and rebuild with **≥5–6-ligand** rank lists for resolution before using it to rank models.
  We do **not** fabricate longer gold ranks; the rebuild is flagged, not invented.

## Consequence for the manuscripts
- RealBio: the wf_gen column is replaced by A (easy, ≈1.0) + B (newly measured). The "0.500 anomaly" the
  committee called a submission blocker is resolved by measurement, not by a footnote.
- DrugDev-Bench: the "dd_spearman leakage [TO BE INVESTIGATED]" line is replaced by the quantization diagnosis
  + the shared-hard-item finding; dd is demoted from a ranking column to a low-resolution probe.
