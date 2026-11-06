# Donor-separated baseline-state evaluation design — 12 September 2026

This is a proposed protocol based on the saved S3 schema/control inspection and current source code. It is not an executed training result. It requires individual-donor pseudobulk counts; existing donor-pair DE matrices do not provide independent donor labels.

## What is established

`dataset_schema.json` records 278,684 pseudobulk rows × 18,129 genes in `GWCD4i.pseudobulk_merged.h5ad`, with sparse X, guide, donor, condition, run, cell counts, UMI counts and eligibility flags. Four donors and three conditions are explicit. `control_feasibility.json` records 720–972 non-targeting profiles passing `keep_for_DE` per donor-condition group. Profiles are not biological replicates. Count values, CSR/CSC encoding attributes and matrix/library agreement must still be checked by the extractor.

The six `GWCD4i.DE_stats.by_donors.h5mu` modalities are all pairs drawn from the same four donors. Splitting those six modalities randomly leaks donor identity. With four donors, donor-disjoint train/validation/test sets cannot each contain a two-donor DE pair. Use individual-donor counts for the new task.

Current `prepare_h1_pilot.py` extracts aggregate-donor DE outcomes, selects successful on-target perturbations, and splits targets. `czi_irm_head.py` accepts target and condition only. Neither can establish a baseline-state benefit or donor generalization without a new input and label contract. The pre-existing successful-perturbation panel is a development panel, not a fresh prospective target sample.

## Extraction contract

1. Freeze the target panel, readout genes, donor IDs, three culture conditions, guide grouping policy, normalization and split seed before looking at new outcomes. Prefer stable Ensembl IDs and reject ambiguous symbol mappings. Retain source row indices and original IDs.
2. Read HDF5 sparse encoding attributes. Read indptr and coalesce selected row ranges for CSR; a CSC matrix requires column-aware extraction. Do not assume the three sparse arrays imply CSR. Extract all non-targeting controls plus the frozen target panel. Inspect the full sparse row to calculate the full-transcriptome UMI denominator before reducing to the readout panel.
3. Reject negative, fractional or nonfinite raw UMI values and malformed sparse indices/pointers. Assert unique observation IDs, nonempty donor/condition/guide keys, positive cell counts and positive library sizes. Verify raw row sums against metadata `total_counts`; investigate discrepancies rather than silently substituting one denominator. Save native string arrays loadable with `allow_pickle=False`.
4. Record every eligibility flag separately. Counts/cell-number QC can define coverage; `keep_effective_guides` or an on-target significance filter conditions evaluation on observed perturbation success. Do not silently treat the composite `keep_for_DE` as outcome-independent QC. Report successful-guide-conditioned results separately if only that cohort is usable.
5. Partition non-targeting **guide IDs** deterministically into feature-control and label-reference pools within donor/condition; keep repeated runs of the same guide together. Each pool must meet a frozen minimum coverage rule. Save pool IDs and assert their intersection is empty. This avoids sharing the same control sampling noise between input and delta label. An optional control-versus-control null uses a third disjoint pool or cross-fitting.
6. Construct the baseline-state input exclusively from feature-control counts. Construct reference expression exclusively from label-reference controls. Sum counts and full-library denominators before transforming: `log1p(10,000 * summed_gene_count / summed_full_library_count)`. Aggregate perturbation profiles by target/donor/condition with an explicit guide weighting policy. The label is transformed perturbation expression minus transformed reference expression. Call it a normalized pseudobulk expression difference, **not** the publication's DE-model log fold change.
7. Missing donor/target/condition groups are unavailable labels, not all-zero effects. Keep measured zero expression and a measured zero difference as valid observations. Save guide/profile/cell coverage for each contrast. Audit target/guide/run composition because a donor effect can be confounded with run or guide coverage.
8. Save source URI, ETag/version if present, byte size, selected-row/gene identifiers, extraction code hash, selected payload hashes, complete transformation manifest and funnel counts. Do not claim a full-object SHA256 after range reads.

The exact aggregation policy needs to be fixed in the implementation. Summed counts weight abundant guides/cells more heavily; equal-guide normalized means answer a different question. A sensitivity comparison is useful, but must not be selected by test performance.

## Evaluation splits and permitted inputs

Primary question: does an observed, unperturbed control state improve response prediction in a donor whose perturbation outcomes were absent from fitting? This is control-assisted donor transfer. It does not demonstrate prediction for a donor with no measured baseline.

Use four outer leave-one-donor-out folds. Within the three remaining donors, use inner leave-one-donor-out validation (two fitting donors, one validation donor) to select a very small frozen hyperparameter grid. Refit on all three outer-training donors and score the untouched outer donor once. Fit feature scaling, outcome scaling, feature selection and any dimensionality reduction only on the applicable fitting donors. If frozen pretrained features are used, report their data provenance and any potential donor overlap.

Primary donor-transfer task uses a predetermined panel of seen training targets. Report test coverage; never fill missing targets. Add a separate, explicitly harder donor-plus-target transfer task: hold out fixed target identities globally from fitting and validation, with separate validation targets if tuning target transfer. Do not blend those two tasks into one score. Avoid the large neural architecture until a ridge baseline demonstrates sufficient signal; four donors give only 12 distinct donor-condition baseline states.

Allowed features: target identity or independently frozen gene representation, culture condition, and feature-control baseline state. Exclude perturbed expression, target effect size/significance, DE baseMean, post-perturbation QC/efficacy measurements and donor-pair DE-derived embeddings. A donor label itself is not a transferable biological feature.

## Required matched comparisons

- No-change and training-only condition-mean effect baselines.
- Training-only target × condition mean for the seen-target donor task; an explicit training condition-mean fallback where absent.
- Target/condition-only predictor versus an otherwise matched predictor with baseline state.
- Training-only ridge with baseline state, using identical labels, splits and loss weights.
- Baseline-state shuffled among training donors **within condition**, preserving all rows that share a state as a group. Do not shuffle rows independently or mix culture conditions. With few donors, enumerate permissible permutations where practical.
- A control-versus-control null to quantify technical effect noise independently of perturbation prediction.

Report unstandardized MSE and per-contrast Spearman with undefined correlations counted/excluded explicitly. Include per-donor, per-condition and coverage results, magnitude calibration and performance excluding the directly perturbed target readout. Equal-weight donor summaries are primary; thousands of genes/guides are not independent donor replicates. Seed variation is optimization uncertainty, not a biological confidence interval. Four outer donors support a development comparison, not a strong population-generalization claim.

## Advancement gate

Advance only if the state model improves paired donor-level errors over strong matched target/condition and ridge baselines, survives the grouped state-shuffle and null checks, and is not driven by the perturbed target gene or one donor. Preserve negative results. Do not label this H1 machinery validation: a baseline-conditioned predictive interface is the first testable step, and the present data remain restricted to this CD4 T-cell experiment.
