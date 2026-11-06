# Immune system audit — 11 September 2026

**Verdict: experimental research system; do not promote to production or describe it as a scientifically validated immune reasoning model.** The saved pilot results reproduce. Reproducibility does not change the negative H1 result or establish independent ATAC donor transfer.

## Coverage and evidence

The audited training worktree is `/Users/kky/biomate-audit-fix`, branch `audit-fix-immune-llm`; the BioMate review worktree is `/Users/kky/biomate-review`. This is an immune-system audit, including its inference boundary, not a claim that the entire BioMate application has been re-audited.

- Inventoried and hashed 401 files under `research/immune_llm_baseline` before fixes; parsed all 132 Python files: no syntax errors. This is a broad static inventory, **not manual semantic review of every legacy file**.
- Manually reviewed the current shared model/context, protein runner, donor and mosaic preparation, mosaic runner/inference, H1 preparation/training/inference, paired-layout adapter, and four checkpoint verifiers; inspected the identified legacy CZI and H4 paths.
- Independently recomputed primary metrics for all **57 runs** from deposited predictions and targets, without importing training metric functions: protein MSE/Pearson, scored ATAC per-peak average precision, H1 masked MSE/row Spearman. All matched within floating-point tolerance. All numeric fields in these 57 prediction archives were finite.
- Reloaded all **57 checkpoints** with restricted Torch loading and reproduced **all saved test predictions**, rather than the earlier shared-pilot verifier's first 64 rows. H1 was tested through the named target/condition interface.
- Recomputed the H1 training-condition-mean baseline directly from deposited training rows. Confirmed disjoint split memberships: cell indices in the first pilot, actual donor IDs in BMMC, ATAC cell indices, and perturbation targets across all H1 conditions.
- The existing 40 regression tests passed before edits; **49 tests passed after fixes**, including sparse explicit zeros, dense/sparse equivalence, feature-type aliases, malformed/missing H1 score inputs, and precision-sensitive fractional counts. Eight fresh subprocess CLI cases also passed, including raw inputs, reordered genes and six invalid-input rejections; valid predictions matched the saved training outputs.
- Read all 7,841,333 stored entries in the current source ATAC matrix: zero explicit stored zeros and zero invalid counts. Thus the sparse-zero defect below is not exhibited by that source's count storage. This read was not a fresh whole-file SHA256 verification of the historical download.

Machine-readable evidence and read-only reproduction scripts are in `20260911_immune_audit/`: `recomputed_results.json`, `checkpoint_results.json`, `atac_source_storage.json`, `recompute.py`, and `checkpoints.py`. The initial recomputation encountered small float32-versus-float64 accumulation differences; comparison uses 2e-6 relative/absolute scale tolerance. No model was refitted in this audit.

## Findings and fixes

| Priority | Finding | Disposition / impact |
|---|---|---|
| High | `prepare_mosaic_pilot.py` converted every stored sparse entry to one. Explicit stored zeros would become false positive accessibility labels; dense matrices also lacked `.tocsr()`. | Fixed with validated CSR conversion, duplicate consolidation, zero elimination, then binarization. Dense/sparse and explicit-zero regressions pass. Current source has no stored zeros; existing ATAC metrics remain reproducible. |
| Medium | `normalize_multiome` accepted aliases such as GEX/ATAC but preserved them, whereas downstream preparation selected exactly Gene Expression/Peaks. Valid supported input could yield empty feature groups. | Fixed canonical feature types in the returned copy; input remains unchanged. Alias regression passes. |
| Medium | H1 `score` silently truncated rows through `zip`, accepted malformed masks/nonfinite observed values, emitted NaN MSE for empty observations, and labeled insufficient-observation rows as constant targets. | Fixed explicit alignment, boolean-mask, finite-observation and nonempty checks; separate exclusion counters. Existing fully observed scores are unchanged. Missing unobserved values remain excluded. |
| Medium | All 15 first-pilot external prediction archives store `cell_ids` as object arrays, which cannot be read with `allow_pickle=False`. Earlier verifier checked markers and predictions but never loaded cell IDs. | Future writer fixed to native Unicode. Historical archives remain unchanged to preserve provenance; numeric predictions remain safely readable. Metadata migration is still required before these archives become a general interchange format. Do not enable unrestricted pickle loading as a general workaround. |
| Medium | Protein/donor preparation checked some counts only after conversion to float32; a fractional value could round to an integer. The paired adapter also tolerated small fractions. | Fixed validation before conversion and exact integer checks. Two precision-sensitive regressions pass. Existing source processing is not refitted. |
| High, legacy | `load_czi_perturbseq.py:188` calls untestable effects “no measured shift” and replaces NaN with zero; `train_czi_irm.py:119` uses 0.069/0.060 historical floors and falls back after floor-file errors. | Not repaired in this pass: changing the loader requires migrating its downstream callers and re-evaluating affected legacy runs. Those runs cannot establish a current matched-baseline gate. The new H1 pilot uses an explicit observation mask and recomputed baseline, bypassing this loader's effect conversion. |
| High, scientific claim | H4 source text calls a single-cell-line count correlation a validated mechanism. Its documented inputs include the held-out KO's measured proteome fingerprint and abundance. | Conditional prediction given post-perturbation measurements must be distinguished from prospective prediction from baseline state. This audit does not accept the mechanism/causal claim or validate legacy H4 outputs. H4 requires its own raw-data and estimand audit. |
| Medium, architecture | Latest pilot losses do not train annotation, study-adversarial, contrastive or variational-KL objectives, despite these heads existing in the factory. All mosaic study indices are zero. | The architecture supports these components, but current fits do not establish their benefit or batch invariance. No functional code change warranted solely to make the architecture look complete. |
| Medium, operational | 202 broad exception handlers across the pre-fix Python inventory; several legacy acquisition/reporting paths log and continue or substitute values. | Static risk inventory, not 202 confirmed bugs. Current active pilots stop on nonfinite training loss and most schema failures. Legacy entrypoints need separate execution-specific triage; a syntax pass is insufficient. |

## Architecture actually trained

RNA is normalized on the selected gene vocabulary and passed through a dense trunk. Optional masked protein/ATAC encoders and confidence-weighted typed RNA-gene graph messages enter the same hidden representation. Shared biological latent means feed protein and ATAC decoders; an RNA negative-binomial decoder also uses a nuisance branch. The CITE and multiome cells come from separate assays; they are not fabricated three-modality paired cells. Whole-modality dropout supports evaluation with RNA alone.

The graph does **not** represent measured peak-to-gene regulation or a validated causal machinery graph. A nuisance branch's presence alone does not demonstrate removal of study information. The model factory's virtual-cell sampling also does not validate generated cells.

H1 is a small head using a frozen RNA projection's gene columns plus culture-condition indicators. It does not accept baseline cell state and does not jointly train the shared encoder. H2/H3/H4 are not newly integrated by this cycle. BioMate reasoning remains a system-level interface using existing LLMs, retrieval, tools, provenance and confidence controls; this biological pilot is not a separate reasoning LLM.

The version-2 mosaic CLI outputs centered log1p protein estimates and uncalibrated selected-peak accessibility scores. The older smoke adapter has different protein units and must not consume these checkpoints. No BioMate production route is connected. Readiness JSON correctly says production is disallowed, but metadata alone is not a deployment enforcement mechanism.

## Data and evaluation interpretation

| Evaluation | Confirmed result | What it supports / limits |
|---|---|---|
| First external protein pilot, 15 fits | Full-model mean MSE about 5.383 vs ridge 5.027; Pearson about .232 vs .330. | No superiority. Within-training cell split; external donor independence and clone calibration unverified. |
| Donor protein pilot, 24 fits | Centered full-model MSE about .5372 vs ridge .5387; shuffled graph about .5351. | Small MSE difference does not establish KG benefit. Two actual test donors, reused in later development. Raw-log and centered-log MSE are different targets and must not be compared as one scale. |
| Joint mosaic, 9 fits | Paired ATAC per-peak AP about .1724 vs ridge .1510, frequency .1371 and shuffled .1358. Protein MSE about .5342 vs extra-RNA-only .5328. | Within-sample ATAC predictive signal; no protein improvement demonstrated by adding ATAC. Epoch selected on protein validation, while ATAC ridge uses ATAC validation MSE: not an identical selection objective. |
| H1, 9 fits | Encoder head mean Spearman about .0319 vs training-condition mean .053260; MSE about .1043 vs .099859. | Gate failed. Random features and shuffled training effects are competitive. Constant-prediction Spearman zero is an explicit convention, not a mathematically defined correlation. |

BMMC splits use actual donor IDs, not batch names: donor 15078 spans four batches but stays in one fold. Gene selection is inherited from an earlier development vocabulary; it is not a fresh genome-wide benchmark. Extra-GSE training is not compute-matched by optimizer-step count. The ATAC test is within a single donor/sample. The additional donor assay has zero exact matches to the 512 frozen peak intervals; zero-filling would invent negative observations and is prohibited. Common-interval fragment quantification is required for valid transfer evaluation.

H1 holds all culture conditions of a perturbation target in one fold, but uses effects aggregated across donors and selects successful on-target perturbations. It does not test donor transfer, unsuccessful perturbations, all genes, or cell-state dependence. Three random seeds measure training variation, not independent cohort uncertainty. Prior full-corpus RNA results predate the selected-feature library-size correction and must not be presented as results of corrected training.

## Error log and reproduction limits

The audit itself caught: object-array metadata loading failures; tiny numeric accumulation differences; and one staging test invocation that imported an older `/tmp` module because of its working directory. The tests were rerun from the correct staging directory and then the actual training directory; both passed the intermediate 47 tests; the final 49-test run also passed. Initial S3 access failed in the restricted network environment; the authorized source read subsequently succeeded. These are execution records, not hidden successful checks.

This pass did not reacquire every raw training dataset, independently establish donor identity from genotype, revalidate every source publication, recompute every legacy H2–H4 output, or rerun the BioMate frontend/backend. It also did not refit every ridge baseline; the H1 condition baseline was independently rebuilt, while other saved baseline values are reported with their documented protocols. Historical verification files were preserved rather than overwritten.

## Next work in priority order

1. Migrate legacy missingness and historical-baseline paths, then rerun affected gates before using their scores in any aggregate readiness claim.
2. Freeze the current development results. Establish a new donor/assay validation set with comparable ATAC intervals and a matched model-selection protocol. Do not optimize against the already-used BMMC test donors.
3. Audit H4's raw labels, censoring, and availability of prospective inputs; revise claims to match the actual prediction task. Do not claim causal validation from a count correlation.
4. Improve H1 only with baseline cell-state information and matched nulls/baselines. Current negative result is a stopping gate for promotion, not a reason to lower the benchmark.
5. Add service-level schema/readiness enforcement and run BioMate end-to-end tests only after a scientifically eligible model is selected. Preserve experimental status in the meantime.

Audit fixes do not require repeating the 57 fits: they change malformed-input handling, storage format for future outputs, and a sparse representation case absent from the inspected ATAC source. Any migration of legacy labels or change to training objectives will require new, separately identified runs.
