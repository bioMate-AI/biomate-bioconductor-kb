# Spark immune-system status — 2026-11-07 18:03 CST

## Verified resources and scope

Host spark-d816.local; immune project /home/yzhang/immune_fm_spark. Peptide projects excluded. GB10 idle at inspection; 116 GiB available RAM; approximately 1.42 TB decimal free disk. Earlier pip-cache cleanup reclaimed approximately 22 GiB. No training Python process was observed.

NGC PyTorch 25.04 CUDA matrix forward/backward smoke test passed with finite gradients (PyTorch 2.7.0a0+79aa17489c.nv25.04). The image prints a GB10 compatibility warning; this small check does not certify a full training workload.

## Latest completed run identified

fs_long completed successfully October 28 at 15:04:25 UTC, after six warm-start continuation epochs. Reported corpus: 22,065,317 rows, 714 studies, 21 cell types; these are metadata counts, not an independent provenance audit or counts of patients. Proto backbone, free bottleneck, batch defense enabled, seed 0.

Launch log establishes a 21,427,922-row RNA base and appended TCR, protein, and ATAC observations. Knowledge channel contains 512 pathway and 256 TF features. These derived features are not additional measured omics. This run does not establish integration of every collected modality or every knowledge skill.

Checkpoint: /home/yzhang/immune_fm_spark/fs_long/work/hybrid_model.pt
SHA256: 04da405dcdd8f4a2cf3ffca3058a3dd03804caae4e50a9c14db19f272ea637a7

Current remote code_20261004/immune_hybrid_llm.py SHA256: 50ec5df564ddc062910fd6fa1882efc2645959ba8ea5f3092e97335270b276b8. Current file hash alone does not prove launch-time code identity.

The completion log records model and metrics upload to s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/immune_llm_models/immune_mosaic_long_20261028/. Remote S3 object contents were not independently checked in this inspection.

## Reported results and limits

| Metric | Value | Interpretation |
|---|---:|---|
| Best validation annotation macro-F1 | 0.3063 | Epoch 2; final epoch 0.2848 |
| Selected-model held-out annotation macro-F1 | 0.3429 | Different split from validation |
| Frozen representation probe macro-F1 | 0.3386 | Raw HVG 0.2950, matched PCA 0.2893 |
| Raw+representation annotation LOCO F1 | 0.3822 | Raw 0.3324; only six evaluated cohorts |
| Target expression model AUROC | 0.4172 | Below coexpression 0.5270 |
| Target latent model AUROC | 0.5907 | Above coexpression, below degree null 0.9359 |
| Perturbation weighted correlation | 0.5793 | Reported DRF 0.1349; 256 KOs |
| Pooled few-shot F1, k=256 | 0.4745 | Not within-study few-shot validation |

Target genetics-prior AUROC 0.585 uses a different gene universe and is not a head-to-head comparison. Study information remains recoverable in validation (leakage ratio about 16; conditional ratio about 4). Perturbation NIR 0.887 is provisional because the current NIR implementation gives full credit to distance ties. Strong responder LOCO figures (raw+z AUROC 0.9915 versus raw 0.0859) require label provenance, patient separation and feature audits before biological interpretation. Virtual-KO top hits are dominated by ribosomal genes; enrichment alone does not establish immune specificity.

## Next execution order

1. Preserve existing checkpoints and results; recover exact launch configuration, data manifests and code identity. Check encoder tensor compatibility before loading.
2. Repair and test fold-local normalization in finetuning, required encoder-key checks, within-study few-shot sampling, and tie-aware identification metrics. Preserve historical metrics under their original protocol names.
3. Audit responder labels and patient/cohort separation; treat current extreme responder performance as unvalidated.
4. Run a small corrected evaluation on Spark in a new output namespace, with raw/PCA controls and frozen representation. Validate finite losses/gradients and artifact provenance.
5. Expand to matched UCE/CAPTAIN comparisons and a functional perturbation endpoint. Resume training only with an explicit objective and a valid evaluation capable of measuring its benefit.

No new full training was launched during this resource inspection. The next work is evaluation repair, not continuation of the degrading six-epoch trajectory.

Raw reports are retained in 20261107_spark_immune_status/hybrid_train.json and rolling_eval.json with payload hashes. They contain legacy NaN values and should not be assumed strict interoperable JSON.
