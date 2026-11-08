# Parallel immune development — 12 September 2026

**The new data pipeline is operational, but the model advancement gate remains unmet.** Parallel lanes completed control extraction, donor/split design, donor-pair replication, module review and an actual donor-held-out baseline-state evaluation. No larger neural run or production deployment is justified by these results.

## What changed

- Added precision-preserving numeric aggregation, rejection of infinite correlations/effects, and unambiguous nonempty gene mapping. Nine adversarial regressions supplement the earlier 61-test suite.
- Extracted 348 non-targeting pseudobulk profiles, 132 frozen genes and 24 donor/condition/control-pool aggregates. Feature and reference pools use disjoint guide IDs; full-transcriptome library sums exactly match source metadata.
- Extracted 384 targeting profiles for 16 targets, two guides each, all four donors and three conditions. Preserved counts, cell support, guide IDs, source rows and source ETag. Fixed five newly generated metadata arrays from object dtype to native strings before any fitting; numerical NPY members were unchanged. The corrected writer is saved with the extraction artifacts.
- Extracted 480 donor-pair DE contrasts, representing 40 selected targets and 132 readouts. Missing values are explicit. Complementary underlying donor sets define the replication comparisons.
- Added a baseline-state ridge evaluation with four outer donor holdouts, all 12 inner donor-validation splits, training-only scaling, matched baselines and grouped shuffled-state controls. It independently verifies raw control pools and source-row disjointness before fitting.

Non-targeting eligibility in this source exactly matches basic cell/count QC. Targeting eligibility also applies effect/test-gene filters: 14,445 targeting profiles are excluded beyond basic QC in the full metadata. Our frozen pilot therefore evaluates an efficacy-conditioned development panel, not an unbiased prospective target sample.

## Results

| Check | Result | Interpretation |
|---|---|---|
| Control feature/reference agreement | Mean across-gene Pearson .9973; after removing condition means, donor-centered agreement .877–.898 | Baseline expression is measurably reproducible between guide pools; not predictive validation. |
| Known-perturbation donor-pair replication | Same-target row Spearman .280–.314 vs condition means .166–.221 and shuffled assignments .059–.068 | Selected effects have cross-pair rank signal; observed effects are being transferred, not inferred by a learned model. MSE improved only 3/6 directions. |
| Target/condition ridge, individual-donor holdout | MSE .017503; Spearman .082250 | Stronger matched comparator for the state arm. |
| Baseline-state ridge, identical donor splits | MSE .018195; Spearman .072590 | Worse on every held-out donor in this pilot; no demonstrated state benefit. |
| After excluding the directly perturbed readout | No-change MSE .015534 vs target/condition ridge .016170 and state ridge .016854 | Downstream predictive signal is not established by the learned arms. |

State labels are independent-reference, full-library-normalized log1p pseudobulk differences, **not published DE log fold changes**. The data comprise 192 target/donor/condition labels and only 12 distinct donor-condition states. Target/condition combinations are seen in training; this does not test unseen-target generalization. Ridge selection uses all-readout inner-donor MSE; target-excluded scores are secondary. Four donors and three complementary donor-pair partitions cannot be inflated into hundreds of biological replicates.

## Verification and location

The integrated suite passes 81 tests: 70 module regressions and 11 donor evaluator contract/split/scaling tests. Its independent verifier reconstructed all 192 labels and states from selected counts, checked all donor splits and independently recomputed 48 metric comparisons. The evaluation performed 120 small ridge fits including tuning; these are not independent experiments. Fitted ridge objects were not saved as serving models; predictions, exact inputs, split indices and hyperparameter grids are retained.

Detailed reports and evidence under `/Users/kky/biomate-review/docs/`:

- `20260912_s3_continuation/baseline_state_data/CONTROL_QUALITY.md`
- `20260912_s3_continuation/pair_effect_data/REPLICATION_REPORT.md`
- `20260912_s3_continuation/donor_state_evaluation/REPORT.md`
- `20260912_s3_continuation/module_review.md`
- `20260912_s3_continuation/donor_evaluation_design.md`

Raw selected arrays, manifests, source snapshots and predictions are also copied to `/Users/kky/biomate-audit-fix/out/20260912_parallel_donor_state/`. Extraction used bounded ranged reads, not a full 44 GB pseudobulk download. Control and target sparse rows account for about 125 MB of logical uncompressed reads together; transport/chunk overhead is not measured. Dataset counts and fitted predictions were not uploaded to S3.

The previously approved S3 code release remains commit `68ad377eee7cba53dae8338bde8ea27842e8b481`. These newer module/evaluation changes are local; the legacy S3 code prefix is unchanged.

## Next decision

Preserve this negative result rather than scale the same model. Diagnose guide/run effects and control-vs-control effect noise, then preregister a broader target panel and independent donor coverage. Any target-excluded optimization is a new development protocol, not a reinterpretation of this test. A state-interaction model may be a future hypothesis, but the present additive ridge result does not establish its benefit. H4 raw-label/censoring and prospective-input auditing remain separate outstanding work.
