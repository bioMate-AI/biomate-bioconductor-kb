# Bounded real-checkpoint evaluation

Date: 2026-11-07T19:09:14.653389-06:00

Completed CUDA integration test: 1,024 sampled cells, six arms, finite predictions; all 78 checkpoint tensors loaded. The first sample export failed on AnnData nullable-string serialization and was corrected explicitly. No OOM occurred.

Completed preliminary evaluation: GSE261278 D534, 15,000 cells, 18 cell-type groups, three GroupKFold folds, one seed, three epochs, labelled training-only scaling. Labels are stimulation status. This is held-out-cell-type evaluation within this dataset, not held-out-patient or independent-study generalization. RNA: 1,988/2,000 checkpoint genes aligned; protein: 29/35 slots mapped. Missing slots are zero-filled. No claim is made that all training modalities were supplied.

| Input | Arm | Label fraction | AUROC | AUPRC |
|---|---|---:|---:|---:|
| rna | pretrained | 0.1 | 0.8395 | 0.4679 |
| rna | pretrained | 1.0 | 0.9695 | 0.9034 |
| rna | scratch | 0.1 | 0.9138 | 0.7730 |
| rna | scratch | 1.0 | 0.9649 | 0.9008 |
| rna | pretrained_frozen | 0.1 | 0.3703 | 0.1108 |
| rna | pretrained_frozen | 1.0 | 0.9182 | 0.7284 |
| rna_protein | pretrained | 0.1 | 0.8650 | 0.5467 |
| rna_protein | pretrained | 1.0 | 0.9723 | 0.9088 |
| rna_protein | scratch | 0.1 | 0.9322 | 0.8278 |
| rna_protein | scratch | 1.0 | 0.9696 | 0.9138 |
| rna_protein | pretrained_frozen | 0.1 | 0.4330 | 0.1293 |
| rna_protein | pretrained_frozen | 1.0 | 0.9155 | 0.7309 |

Memory: process maximum RSS 2.44 GiB; PyTorch peak allocated 134.8 MiB; reserved 164.0 MiB. Container host limit 12 GiB, no swap allowance beyond that cap, two CPUs, one GPU job. Unified/GPU memory accounting may differ from process/cgroup accounting. These results do not prove full-corpus training fits.

All 12 saved prediction arrays cover all 15,000 rows with finite probabilities. Strong performance on stimulation detection is not evidence of target discovery, druggability or therapy-duration validity. A longer three-seed comparison is being run separately; the short-run results above remain preserved.

## Completed three-seed, 12-epoch follow-up

All 36 configurations completed (108 fold fits), with finite out-of-fold predictions for all 15,000 cells. Same group splits, seed-matched label subsets and optimizer settings across arms. Seeds 0/1/2; label fractions 0.1 and 1.0. Scores below are seed mean ± sample standard deviation, not confidence intervals.

| Input | Arm | Label fraction | AUROC | AUPRC |
|---|---|---:|---:|---:|
| rna | pretrained | 0.1 | 0.9124 ± 0.0517 | 0.7486 ± 0.1310 |
| rna | scratch | 0.1 | 0.9448 ± 0.0081 | 0.8302 ± 0.0122 |
| rna | pretrained_frozen | 0.1 | 0.7174 ± 0.0882 | 0.3567 ± 0.1401 |
| rna | pretrained | 1.0 | 0.9707 ± 0.0008 | 0.9215 ± 0.0045 |
| rna | scratch | 1.0 | 0.9634 ± 0.0035 | 0.9049 ± 0.0033 |
| rna | pretrained_frozen | 1.0 | 0.9520 ± 0.0013 | 0.8688 ± 0.0114 |
| rna_protein | pretrained | 0.1 | 0.9279 ± 0.0253 | 0.7629 ± 0.0905 |
| rna_protein | scratch | 0.1 | 0.9506 ± 0.0084 | 0.8566 ± 0.0195 |
| rna_protein | pretrained_frozen | 0.1 | 0.7247 ± 0.0853 | 0.3783 ± 0.1199 |
| rna_protein | pretrained | 1.0 | 0.9715 ± 0.0013 | 0.9206 ± 0.0059 |
| rna_protein | scratch | 1.0 | 0.9673 ± 0.0108 | 0.9211 ± 0.0114 |
| rna_protein | pretrained_frozen | 1.0 | 0.9436 ± 0.0006 | 0.8617 ± 0.0066 |

Elapsed 205.0 seconds; peak RSS 2.28 GiB; CUDA peak allocated 134.8 MiB, reserved 164.0 MiB.

Interpretation: transfer is task- and budget-dependent. This experiment does not establish a robust general pretraining advantage. AUPRC matters given 2,141 positives among 15,000 cells. The pooled metric across three held-out cell-type folds is not donor-level validation. Pretraining overlap with this external dataset remains unaudited; this is not certified unseen-data transfer. Fold-local scaling is shared across arms but differs from pretraining normalization, which particularly affects a frozen encoder.

Next: verify label semantics and dataset/pretraining overlap; add a matched linear baseline and cohort/donor separation where metadata supports it; replicate on the perturbation dataset before changing pretraining objectives. Large-corpus training remains a separate memory-engineering problem; continue streamed loading rather than dense corpus materialization.

Execution notes: the first longer-launch attempt accidentally retained the short settings; its outputs are preserved remotely under short_retry/. The completed file was explicitly checked for 12 epochs, all three seeds and 36 configuration rows. An unavailable /usr/bin/time was replaced with Python resource measurements. No historical checkpoints were overwritten.
