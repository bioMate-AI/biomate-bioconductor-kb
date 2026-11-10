> Interpretation update (2026-11-08): a missing CP10k transform and omitted derived knowledge channel were identified. Numbers below remain historical pipeline results; see [20261108_0106_CST_IMMUNE_INPUT_CONTRACT_AUDIT.md](20261108_0106_CST_IMMUNE_INPUT_CONTRACT_AUDIT.md) before interpreting representation quality.

# Immune transfer diagnostic: fixed labels, matched optimizer updates

Timestamp: 2026-11-07T21:35:03.497050-06:00

## Finding

Insufficient optimization contributes to the observed low-label deficit under this protocol, but does not fully explain it. Increasing updates improved pretrained mean AUPRC and reduced its seed variability. Scratch still led at the matched endpoint. This supports correcting the earlier equal-epoch interpretation; it does not establish a general advantage for pretraining or a unique biological mechanism.

## Controlled comparison

Same fs_long checkpoint, RNA features, 15,000-cell GSE261278 dataset, three cell-type-disjoint folds, seeds 0/1/2, 10% labelled subsets, labelled-only scaling, AdamW learning rate 3e-4 and batch size 256. Each training trajectory was evaluated at two prespecified endpoints: 48 updates (12 epochs on the labelled subset), then 468 or 480 updates (the count from 12 epochs using all outer-training labels). Both endpoints still train on exactly the same 989–1,008 labelled cells per fold. No outer-fold selection of the better endpoint.

The fixed-epoch predictions reproduced all six original RNA/10%-label prediction arrays exactly, element for element. All 12 new prediction arrays are finite. Saved split indices are disjoint; labelled-subset hashes match between arms and endpoints.

| Arm | Schedule | AUROC | AUPRC |
|---|---|---:|---:|
| pretrained | fixed_epochs | 0.9124 ± 0.0517 | 0.7486 ± 0.1310 |
| pretrained | matched_full_label_updates | 0.9305 ± 0.0241 | 0.7934 ± 0.0692 |
| scratch | fixed_epochs | 0.9448 ± 0.0081 | 0.8302 ± 0.0123 |
| scratch | matched_full_label_updates | 0.9392 ± 0.0100 | 0.8183 ± 0.0198 |

Values are mean ± sample standard deviation across three seeds, not confidence intervals. The scratch-minus-pretrained mean AUPRC gap narrowed from about 0.0816 to 0.0249. Both changes contribute: pretrained improves while scratch worsens slightly. This is compatible with different optimization/generalization trajectories. Do not interpret the percentage of gap closure as a causal decomposition or claim statistical significance.

## Label and donor audit

Exact stimulation values: unstimulated 12,859; flu 1,142; sars 999. The current binary mapping is consistent with these observed categories. Observed columns: study, dataset, cell_type, tissue, stim. No donor/patient/subject column was found. The filename alone does not establish donor identity or patient-level replication. Pretraining overlap remains unresolved.

## Resource and validation results

Completed in 95.8 seconds, maximum process RSS 2.20 GiB. CUDA peak allocated 135.2 MiB; reserved 166.0 MiB. Container exit 0 and OOMKilled=false, under a 12 GiB limit with two CPUs and one GPU job. Finite loss, gradients and predictions were checked. These results do not validate full-corpus memory safety.

## Next decision

Keep optimizer-update exposure explicit in subsequent comparisons. Next isolate normalization: fit feature statistics on all outer-training cells without using their extra labels, with inner-split refitting if hyperparameters are selected. Compare this with labelled-only normalization under the same fixed subsets and update counts; label the extra unlabelled-data access explicitly. Then add converged raw and frozen-embedding linear probes and inner-validation learning-rate selection. Do not choose the winning protocol on these already-inspected outer folds and call it confirmatory; freeze a protocol before independent functional replication.

Raw metrics, memory measurements, predictions, exact split indices, executable script and protocol are retained in `20261107_spark_immune_status/update_count_diagnostic/`.
