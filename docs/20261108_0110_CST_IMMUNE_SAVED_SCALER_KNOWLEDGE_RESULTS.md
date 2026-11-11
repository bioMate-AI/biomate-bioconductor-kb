# Saved corpus scaler and knowledge-channel diagnostic

Recorded: 2026-11-08T01:10:20.694035-06:00

## Main finding

The saved corpus scaler materially improved frozen pretrained transfer compared with fold-fitted input scaling. At the prespecified reference C=1, pretrained RNA-only AUPRC increased from 0.5105 to 0.7092. Restoring the RNA-derived pathway/TF channel produced 0.6847, while raw RNA remained 0.8770. Input distribution mismatch therefore accounts for substantial degradation under the tested preprocessing; it does not account for the entire remaining gap. Previous statements dismissing normalization as an explanation applied only to the narrower labelled-versus-all-training-fold scaler comparison, not corpus-versus-target-data scaling.

## Provenance and restoration limits

Retrieved S3 object: `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/immune_llm_models/rna_baseline/stream_cache/stream_hvg_scaler.npz`.
SHA256: `0951a8e2034a2340b22734aa4b026a7d074da13ce4d763ba683da9fb7e10a9c5`.
The embedded staleness field states `<=4 datasets vs final PASS1`. Thus this is an approximate saved scaler, not byte-exact reconstruction. Gene order matched the checkpoint exactly, all means/scales were finite, and all scales were positive.

Knowledge basis regenerated offline from preserved fs_long/work resources and the matching knowledge_channel.py implementation. No S3 refresh occurred. Dimensions matched the checkpoint: 512 pathways plus 256 TF features. Exact resulting membership arrays are saved. Matching dimensions and current preserved sources do not by themselves prove identical historical launch-time membership or ordering.

Resource SHA256 values:
- reactome.gmt: 89983d5c1f0af11c52edfeee7323eb425580ac6281d387a528562ab1787ce56b
- kegg.gmt: 080f877db330cd67ea067d235990aed935d7200f0073b7995e7abb6642695f4e
- go_bp.gmt: b4b3b49a267c2239fad40d39a56f2146a57743992943915e80ebed34ec7ebaae
- tf.parquet.gz: d9e069d0150bd3a4d12c560e8a405dcc6488f1820dd91b439ff732bbace70ecf

## Protocol and full results

Same GSE261278 15,000 cells, three held-out-cell-type folds, three label-sampling seeds and 10% labels. CP10k over all source genes, log1p, checkpoint HVG alignment, then saved corpus scaling before encoding. Final classifier StandardScaler still fits labelled rows only for all feature arms. For raw RNA, that last scaling effectively cancels the preceding affine scaler; unchanged raw scores are expected, not independent evidence of corpus-scaler correctness. Missing source genes are zero-filled before corpus centering; this remains an explicit convention, not per-gene missingness modeling.

Fixed logistic C grid, class balancing and convergence checks unchanged. No selection on outer scores. Knowledge-versus-no-knowledge comparison holds scaler and pretrained weights fixed. Random-with-knowledge is an architecture/initialization control, not a trained scratch model.

| Features | C | AUROC | AUPRC |
|---|---:|---:|---:|
| raw | 0.01 | 0.9563 | 0.8823 |
| raw | 0.1 | 0.9552 | 0.8793 |
| raw | 1.0 | 0.9544 | 0.8770 |
| raw | 10.0 | 0.9538 | 0.8751 |
| pretrained_z | 0.01 | 0.9274 | 0.8348 |
| pretrained_z | 0.1 | 0.8937 | 0.7603 |
| pretrained_z | 1.0 | 0.8708 | 0.7092 |
| pretrained_z | 10.0 | 0.8605 | 0.6823 |
| pretrained_z_knowledge | 0.01 | 0.9235 | 0.8226 |
| pretrained_z_knowledge | 0.1 | 0.8839 | 0.7390 |
| pretrained_z_knowledge | 1.0 | 0.8584 | 0.6847 |
| pretrained_z_knowledge | 10.0 | 0.8475 | 0.6569 |
| random_z_knowledge | 0.01 | 0.8737 | 0.6813 |
| random_z_knowledge | 0.1 | 0.8451 | 0.6020 |
| random_z_knowledge | 1.0 | 0.8344 | 0.5529 |
| random_z_knowledge | 10.0 | 0.8314 | 0.5273 |

Means over three seeds; no statistical significance claim. At C=0.01, RNA-only pretrained AUPRC is 0.8348 versus raw 0.8823. This shows substantial regularization sensitivity but is not a validation-selected optimum. Knowledge addition reduced mean AUPRC at every tested C here; this does not establish that knowledge is globally harmful or that its benefits on other tasks are absent.

## Validation and next steps

All 144 fits converged; 48 OOF prediction arrays are finite with identical labels/groups to the previous count-transform comparison. Container exit 0, OOMKilled=false. Runtime 19.0 seconds; peak process RSS approximately 2.04 GiB. No full-corpus matrix or new pretraining job was launched.

Next implement an explicit reusable inference bundle containing gene order, transform metadata, scaler provenance, exact knowledge membership and masks. Mark approximate scaler provenance prominently; fail on incompatible feature dimensions. Add prediction-parity tests against this diagnostic before using that bundle elsewhere. Do not silently alter historical evaluator defaults.

Then perform inner-group-validation regularization and adaptation tuning under the documented bundle. Keep the present outer folds exploratory and confirm the resulting protocol on an independent audited functional dataset. Donor-level validation and pretraining-overlap audit remain unresolved. Do not use these single-endpoint results to justify broad claims about virtual-cell fidelity or target discovery.

Artifacts: `20261108_restored_input_diagnostic/`, including executable script, generated knowledge membership, raw predictions and provenance metadata. Earlier results are retained.
