# Immune representation transfer: findings and diagnostic plan

Recorded: 2026-11-07T20:05:35.147737-06:00

## Conclusion

The current checkpoint has not demonstrated reliable label-efficient transfer for stimulation prediction. With 10% of training-fold labels, scratch models outperformed fine-tuned pretrained models on average. With full labels, RNA pretraining showed a small improvement; RNA-plus-protein AUPRC was essentially tied. This is a task-specific finding, not evidence that immune pretraining is generally ineffective or a reason to build a do-everything LLM.

The system goal remains useful representations that augment downstream task models, with provenance-aware knowledge retrieval and reasoning evaluated separately.

## Experiment and evidence

GSE261278 D534: 15,000 cells, 2,141 stimulation-positive cells (14.27%), 18 cell-type groups. Three GroupKFold folds, seeds 0/1/2, 12 epochs, learning rate 3e-4, batch size 256. Label fractions 0.1 and 1.0 are sampled within each training fold. All arms use the same sampled labels for a given seed. Normalization statistics use the labelled training subset only. RNA has 1,988/2,000 checkpoint genes; protein has 29/35 mapped slots, with missing slots zero-filled.

Checkpoint SHA256: 04da405dcdd8f4a2cf3ffca3058a3dd03804caae4e50a9c14db19f272ea637a7. All 78 saved trainable tensors loaded. This checkpoint is the fs_long selected model, not the capped B2 checkpoint used in earlier few-shot results.

All 36 configurations (108 fold fits) completed. All saved out-of-fold prediction arrays are finite and cover all rows. Container exit 0, OOMKilled=false. Runtime 205 seconds; maximum process RSS 2.28 GiB; PyTorch peak allocated 134.8 MiB and reserved 164.0 MiB. These measurements establish feasibility for this evaluation, not full-corpus training.

| Input | Labels | Pretrained AUROC | Scratch AUROC | Pretrained AUPRC | Scratch AUPRC |
|---|---:|---:|---:|---:|---:|
| RNA | 10% | 0.9124 ± 0.0517 | 0.9448 ± 0.0081 | 0.7486 ± 0.1310 | 0.8302 ± 0.0122 |
| RNA | 100% | 0.9707 ± 0.0008 | 0.9634 ± 0.0035 | 0.9215 ± 0.0045 | 0.9049 ± 0.0033 |
| RNA + protein | 10% | 0.9279 ± 0.0253 | 0.9506 ± 0.0084 | 0.7629 ± 0.0905 | 0.8566 ± 0.0195 |
| RNA + protein | 100% | 0.9715 ± 0.0013 | 0.9673 ± 0.0108 | 0.9206 ± 0.0059 | 0.9211 ± 0.0114 |

Values are means ± sample standard deviations across three seeds, not confidence intervals. The frozen encoder with a short-trained neural linear head was worse; this does not establish that an adequately optimized linear probe is weak.

## What we cannot conclude

- Splits hold out cell types within this dataset, not donors or independent cohorts. Cell count is not independent patient count.
- Pretraining overlap has not been excluded; the dataset cannot yet be called certified unseen transfer data.
- No significance test or clinical validation supports the small full-label differences.
- The previously reported low-label advantage used a different checkpoint, endpoint and pooled adaptation protocol; it is not a direct replication or contradiction.
- We have not established the dominant cause of the low-label deficit. The earlier conversational suggestion that adaptation difficulty is the most likely cause should be treated as a hypothesis, not a ranked causal finding.

## Competing explanations and discriminating tests

| Hypothesis | Current evidence | Diagnostic | Interpretation |
|---|---|---|---|
| Too few optimizer updates | Twelve epochs on 10% labels provide roughly one tenth the updates of full labels; the code also skips batches below four rows | Compare fixed epochs with fixed update counts using the same labelled subset; log actual steps | Recovery with more updates implicates optimization exposure, without proving useful representation transfer |
| Fine-tuning learning rate or schedule is unsuitable | One learning rate was shared across all arms; pretrained performance varies by seed | Inner-validation selection of encoder learning rate and head-only warm-up; equal search budgets for comparison arms | Recovery would show protocol sensitivity rather than justify changing pretraining immediately |
| Normalization shifts model inputs | Fold-local labelled-subset scaling is verified; exact pretraining input distribution has not yet been reconstructed | Compare labelled-only scaling with scaling fit on all outer-training-fold cells, using no held-out cells; inspect saved pretraining transform separately | Recovery under all-training scaling implicates feature-statistic estimation or input compatibility; label the extra unlabelled-data access explicitly |
| Pretraining emphasizes cell identity over stimulation | The pretraining objectives and current endpoint differ; no causal attribution established | Converged frozen linear probes, scratch/linear controls and replication on another immune functional endpoint | Consistently poor transfer after optimization controls supports revising the representation objective |
| Label sampling or initialization causes instability | Seed variation is larger for pretrained low-label runs | Separate subset seed from model/head initialization seed and use a small crossed design | Identifies the source of variability; three mixed seeds alone cannot separate it |
| Dataset or label artifacts | Label semantics, donor structure and overlap audit are incomplete | Inspect exact stimulation categories, donor metadata, source identifiers and training manifests | Resolve invalid labels or overlap before making biological/generalization claims |

These explanations can coexist. A single favorable rerun cannot identify a unique mechanism.

## Execution sequence

### 1. Lock provenance and inspect inputs

Retain existing outputs as historical exploratory results. Save dataset, checkpoint and code hashes; exact CLI/environment; cell IDs; held-out groups; labelled subset indices; class counts; actual update counts; missing-feature maps; and normalization statistics or their reproducible hashes.

Audit stimulation category mappings explicitly: unknown/missing categories must not silently become positives. Determine donor availability and whether D534 is a single-donor slice. Reconcile accession and sample identifiers against pretraining manifests. Mark overlap unknown when manifests are insufficient.

### 2. Run the smallest diagnostic first: RNA, 10% labels

Use the existing three outer cell-type folds only as an exploratory diagnostic benchmark. The outer results have already been examined, so they cannot become an untouched confirmatory test by renaming them.

Within each outer training fold, make a group-disjoint inner validation split where class coverage permits. If it cannot support both classes, report the limitation and do not silently substitute a cell-random validation split. Select hyperparameters using inner validation only, then refit on the outer training fold's designated label budget. Scaling must be refit within each inner split; the all-unlabelled-training policy must exclude inner validation cells during selection and outer held-out cells throughout.

Start with four controls: raw-feature regularized logistic regression, converged frozen-embedding logistic regression, scratch neural model, fine-tuned pretrained neural model. Use matching cells, labels and feature availability. Do not treat the existing three- or twelve-epoch frozen head as the converged probe.

Diagnostic axes, introduced in stages rather than one large sweep:
1. Labelled-only versus all-training-cell normalization.
2. Fixed 12 epochs versus equalized optimizer updates at a fixed label budget; record learning curves on inner validation.
3. Encoder learning rates 1e-5, 3e-5, 1e-4 and 3e-4, with separately recorded head rates; equalize search opportunity for scratch. These are proposed grid values, not evidence-backed optimal settings.
4. Head-only warm-up followed by gradual unfreezing if the learning-rate test warrants it.

Use seeds 0/1/2 for initial comparability. If instability persists, cross three label-subset seeds with three initialization seeds for the selected configurations. Share subset seeds across arms. Advance to protein inputs and full-label comparison only after the RNA diagnostic is interpretable.

### 3. Evaluate without selecting on outer results

Primary endpoint: AUPRC, because positives comprise about 14.3% of this dataset. Secondary endpoints: AUROC, calibration, per-held-out-group performance and resource cost. Report pooled out-of-fold scores alongside per-group outcomes; single-class groups have undefined AUROC and must be reported as such.

Compare arms using matched predictions and identical splits. Use group-aware uncertainty estimates with explicit caveats about only 18 groups and the three fitted outer folds. Seed standard deviations are not population uncertainty. Report all registered configurations, failures and exclusions.

Freeze the chosen protocol before confirmatory evaluation on a new cohort or functional dataset. The existing Papalexi perturbation dataset is a candidate, but requires its own label, pretraining-overlap and held-out-perturbation audit; do not assume the current hand-curated regulator-versus-other endpoint establishes causal perturbation prediction.

### 4. Decision rules

- If update-count or normalization controls remove the deficit: repair the evaluation/adaptation protocol and replicate before changing pretraining objectives.
- If inner-selected fine-tuning helps but frozen probes do not: describe a useful initialization, not generally linearly accessible task information.
- If optimized frozen probes help: investigate deployment as a lightweight representation-plus-task-head system.
- If pretraining remains inferior to matched raw/linear/scratch controls across audited functional tasks: revise task-aligned pretraining objectives and modality handling before scaling corpus or epochs.
- A transfer benefit requires improvement on the prespecified endpoint with group-aware uncertainty and independent replication; no numerical success threshold is chosen after seeing these results. Define a practically meaningful margin for the chosen downstream use case before confirmation.

## Spark execution safeguards

One GPU evaluation job at a time. Retain the tested 12 GiB container limit and bounded threads, stream large matrices, and begin each new dataset with a bounded backed slice. Observe process RSS, container memory, CUDA allocated/reserved memory and host available memory together. The container limit alone does not guarantee accounting of all unified-memory allocations. Stop on nonfinite loss/predictions, failed checkpoint compatibility, or a memory guard violation; preserve logs and partial outputs.

Do not materialize the 22-million-row corpus as float32: 22 million × 2,000 × 4 bytes is approximately 176 GB before model/optimizer allocations. This evaluation did not resolve that full-scale memory problem. No claim is made that the November 5 host OOM events originated from this immune project.

## Evidence locations and status

- Detailed results: [real evaluation report](20261107_spark_immune_status/real_evaluation/REPORT.md).
- Metrics: [three-seed result JSON](20261107_spark_immune_status/real_evaluation/gse261278_3seed_12epoch.json).
- Predictions: `20261107_spark_immune_status/real_evaluation/gse261278_3seed_12epoch_oof.npz`.
- Code snapshots and tests: `20261107_spark_immune_status/eval_repair/`.
- S3/OOM reconciliation: [audit](20261107_spark_immune_status/FOLLOWUP_OOM_AND_EVALUATION.md).

Completed: evaluation repairs, six helper regression tests, real-checkpoint smoke test, short and three-seed evaluation, prediction validation, memory inspection. Planned, not yet executed: the causal diagnostics, nested tuning, converged linear controls and independent functional replication described above.
