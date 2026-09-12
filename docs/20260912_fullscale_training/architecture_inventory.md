# Full-scale architecture inventory — 2026-09-12

Scope: read-only inspection of `/Users/kky/biomate-audit-fix/research/immune_llm_baseline`. No training launched, no remote checkpoint existence verified. No AGENTS.md was present at repository, research, or module level.

## Actual implemented paths

| Path | Layers and inputs | Actual objectives / limits |
|---|---|---|
| `train_expanded_neural.py` | Target/condition one-hot, optional 132-gene baseline state; residual MLP input→64 ReLU→512 output, training-only shrinkage offset | Downstream residual MSE. Explicitly asserts 384 contrasts/32 targets, four donors. This is the current expanded experiment, not a foundation-model run. |
| `b2_train_encoder.py` + `immune_hybrid_llm.py` | Defaults d128/bottleneck64, two-layer four-head transformer stub; RNA and pathway channels; knowledge2 masked pathways (two projections/pathway) + eight de-novo nodes | Annotation, linear annotation, gene-weight annotation proxy, contrastive, adversarial study loss, genetics prior, pathway sparsity. Corpus driver disables biomarker and responder weights. Loads capped assembled v7 cache, not every raw cell. |
| `b2_1_xverse_encoder.py` + `xverse_model.py` | Two linear/LayerNorm/ReLU trunk layers; biological and study-conditioned nuisance Gaussian latents; two-layer decoder and NB count mean; annotation, study, contrastive heads | RNA NB likelihood, KL, annotation, study contrastive/adversarial losses. Current full-corpus launcher is expressly RNA-only; optional omic/KG components are not populated by this driver. |
| `train_mosaic_pilot.py` + shared XVERSE | Adds protein/ATAC masked encoders and reconstruction heads, typed gene-graph context | Protein MSE, ATAC BCE, RNA NB. Pilot cohorts/feature panels, not corpus-wide unified training. |
| `train_immune_fm.py` | Defaults eight-layer/eight-head d512 expression transformer; 1,024 top genes/cell, 51 expression bins | Masked-bin prediction, cell-type SupCon, study adversary. Pools whole supplied arms in memory; no held-out split in this script. No paired omics/KG/clinical/perturbation objective integration. |
| `train_immuno_llm.py`, `train_qwen.py` | Separate text-model LoRA/QLoRA paths | Instruction/disease text tasks and literature retrieval; not joint gradients into cell encoder. These legacy scripts do not implement the accepted BioMate reasoning-interface system by themselves. |

## Confirmed wiring errors/gaps to address before claiming all layers/objectives

1. **Knowledge2 bypasses the backbone and omic fusion.** `immune_hybrid_llm.py` forward computes `fused`, then knowledge2 defines z entirely from pathway-projected `expr`. Consequently downstream heads do not backpropagate into transformer, omic encoders, or fusion in this arm. Knowledge bottleneck v1 has the same bypass. Training every advertised layer requires a deliberately integrated residual/gated design and gradient-coverage tests, not just enabling the arm.
2. **Generic batch slicing omits task labels.** `slice_batch` emits base fields and optional protein/ATAC/TCR, but no peptide features, immunogenicity, presentation, durability or inflammation labels. The joint loss's optional task branches therefore cannot activate through this generic trainer. Add explicit per-task observed-label masks and dataset-specific collators; missing labels must not become negatives.
3. **The target head is a cell-type classifier on expression.** Its CE against `y` is not experimentally grounded perturbation-response prediction or causal target validation. Real perturbation conditioning, control-state inputs, intervention labels and held-out donor/target evaluation need a distinct head/loss path.
4. **Real hybrid loader exposes RNA+knowledge only.** Default synthetic config advertises protein/ATAC/TCR; real config does not establish full-scale availability. The newer shared context supports feature-level masks and typed graph edges, but the B21 corpus driver must actually supply them.
5. **Checkpoints are weights-only.** B2/B21 save state_dict and infer next epoch from object name, not optimizer/scheduler/RNG/sampler state or complete immutable schema/config fingerprints. Resume is not trajectory-exact and can reuse same-shaped incompatible data. Full-scale runs require versioned run manifests and full state checkpoints.
6. **No unified all-objective trainer exists in the inspected paths.** Peptide-HLA, clinical, perturbation, RNA/ADT/ATAC, pathway/genetics and literature interfaces are separate. A multi-source task scheduler, loss availability/weights, shared feature registry, train/eval split registry and loss/gradient coverage report are concrete missing integration, not a missing command-line flag.

## Existing launch/checkpoint paths

`run_b21_full_corpus_ablation_ec2.sh` runs smoke then full/contrast/adv arms, 10 epochs, CPU Torch, 8-hour shutdown. Reads `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/immune_llm_models/P4_linear_advantage/assembled_v7_capT100_capVT800.npz`; writes an isolated date-run prefix below `.../immune_llm_models/B21_full_corpus_ablation/`. Its own report explicitly says RNA-only, single seed, no knowledge/causal/multi-omic integration tested. "Full" means its assembled capped cache. Source archive is expected remotely; current local changes are not thereby deployed.

B2 default checkpoint prefix is `.../immune_llm_models/B2_encoder/`, filenames `ckpt_<arm>_s<seed>_ep<epoch>.pt`. B21 uses `ckpt_b21_s<seed>_ep<epoch>.pt` and final. This audit establishes code paths, not current S3 checkpoint completion.

## Concrete implementation sequence

1. Build an immutable manifest of every eligible corpus and its donor/study partition, measurement schema, label provenance and usable objective. Report discovered, eligible, train and held-out counts separately; all eligible training data does not include held-out rows or fabricated modality labels.
2. Use shared XVERSE context as the existing omics/KG integration substrate; stream/shard uncapped RNA and real paired measurements. Wire RNA NB/KL plus observed protein/ATAC reconstruction, typed graph context, and annotation/contrastive/adversarial terms. Preserve feature-level masks and full-library count semantics.
3. Add intervention-conditioned response and peptide/clinical task batches only with real labels. Stage objectives according to data availability while sharing the intended representation; log effective supervised examples per loss and per-layer nonzero gradients.
4. Implement exact checkpoint/resume and run identity validation; execute a finite real-data integration batch for every configured loss, then launch the manifest-defined full training schedule. Keep large-run evaluation independent and no-change/null/baseline gates explicit.
5. Keep external knowledge retrieval and BioMate reasoning outside model weight training where provenance/currentness matter; graph/pathway/genetics priors can additionally participate in the model. Do not conflate literature QA tuning with omic prediction training.
