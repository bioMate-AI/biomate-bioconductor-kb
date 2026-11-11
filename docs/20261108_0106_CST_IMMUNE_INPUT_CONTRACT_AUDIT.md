# Immune training-to-inference input contract audit

Recorded: 2026-11-08T01:06:37.381198-06:00

## Correction to prior interpretation

The transfer evaluator did not match the documented pretraining count transform. Therefore prior results establish behavior of the tested transfer pipeline, not a clean estimate of intrinsic pretrained representation quality. The earlier conclusion that weak frozen results exclude preprocessing explanations was too strong. Prior numerical results remain reproducible; their interpretation requires this qualification.

## Verified findings

1. Training stream code applies CP10k library normalization to recognized raw-count sources, then log1p, then a corpus-training-derived per-gene scaler and HVG selection. Already-log inputs are passed through by a heuristic. Local and remote stream_corpus.py hashes match: e03761227479a8a8cd21b0fa2be67f16ec7d3bb06e71a10b4ff963e6633429a1. This verifies current code identity, not historical execution provenance by itself.
2. Transfer evaluation applies log1p directly to aligned raw counts, followed by fold-local scaling; CP10k was missing. A bounded initial sample showed integer counts and library sums 961–21,735. The corrected experiment checked all stored nonzero values for finite nonnegative integer counts before transforming them.
3. Training log/provenance indicates an active 768-dimensional RNA-derived pathway/TF knowledge channel. The transfer Clf supplies RNA (and protein in those arms) but no knowledge channel. This is an explicit RNA-only ablation, not training-equivalent inference. Knowledge could be derived from RNA if the exact basis and ordering are recovered.
4. The original corpus scaler is not in stream_cache/meta.json or the checkpoint metadata. recover_stream_scaler.py explicitly describes reconstruction from a potentially stale PASS1 checkpoint, not byte-exact recovery. The bounded local search found no separate corpus scaler file. This does not establish absence from S3. Do not silently treat reconstructed statistics as exact.
5. Strict trainable tensor loading succeeded for the tested model. Nevertheless the checkpoint metadata does not completely serialize preprocessing, knowledge basis/order, fusion choices or all nontrainable state. Tensor compatibility is necessary but insufficient for a reproducible inference contract.
6. Missing modalities are omitted by the wrapper, which the fusion forward path permits; present RNA receives an all-one whole-modality mask. Missing gene slots are zero-filled with no per-gene presence mask. Protein has partial panel overlap. Do not equate whole-modality presence with full feature coverage.

## Controlled count-transform rerun

Changed only the initial RNA transform: CP10k over all source genes before log1p and HVG alignment. Preserved folds, labelled subsets, three seeds, fixed C grid, outer-training normalization, labelled-only classifier scaling, and RNA-only inference. Exact corpus scaler and knowledge channel remain unresolved. Thus this is a count-transform diagnostic, not complete restoration of the training contract.

All 108 logistic fits converged; 36 finite OOF arrays cover 15,000 rows and labels/groups match the earlier probe. No selection of best C was performed.

| Features | C | AUROC | AUPRC |
|---|---:|---:|---:|
| raw | 0.01 | 0.9563 | 0.8823 |
| raw | 0.1 | 0.9552 | 0.8793 |
| raw | 1.0 | 0.9544 | 0.8770 |
| raw | 10.0 | 0.9538 | 0.8751 |
| pretrained_z | 0.01 | 0.8599 | 0.6544 |
| pretrained_z | 0.1 | 0.8234 | 0.5627 |
| pretrained_z | 1.0 | 0.7985 | 0.5105 |
| pretrained_z | 10.0 | 0.7867 | 0.4846 |
| random_z | 0.01 | 0.8462 | 0.5930 |
| random_z | 0.1 | 0.8221 | 0.5192 |
| random_z | 1.0 | 0.8148 | 0.4843 |
| random_z | 10.0 | 0.8122 | 0.4672 |

Values are means over three label-sampling seeds. At reference C=1, raw AUPRC improves from 0.8405 to 0.8770; pretrained AUPRC changes from 0.5131 to 0.5105. Correcting CP10k alone did not rescue frozen transfer. Other regularization settings show different changes; avoid reducing the finding to one cherry-picked metric.

## Next repair sequence

- Recover and hash the original or explicitly approximate corpus scaler from provenance-controlled artifacts; verify gene order and source completeness. Exact absence is not yet established across S3.
- Recover the historical pathway/TF basis and ordering. Avoid using newly downloaded mutable gene sets without documenting changed semantics.
- Introduce an explicit transform contract: raw counts versus already-normalized expression, library normalization before gene subsetting, gene order, fitted scaler provenance and missing-gene convention. Unknown input state should fail rather than be silently guessed.
- Compare corrected RNA-only and RNA-plus-derived-knowledge inference on matched splits. No external held-out labels may enter feature construction.
- Only then use inner-group-validation tuning and independent functional replication to assess representation or objective changes. Keep full-scale pretraining paused until those controls are interpretable.

Historical reports retain their original numbers with an added interpretation notice. The corrected diagnostic is isolated in `20261108_input_contract_audit/`; historical checkpoints and production evaluator code were not overwritten by this diagnostic.
