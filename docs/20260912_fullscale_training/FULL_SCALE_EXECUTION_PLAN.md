# Full-scale immune model execution plan

Updated 2026-09-12. User instruction: full-scale training with all data, knowledge, layers and objectives. This replaces the capped RNA and 32-target pilot as the implementation destination. No full-scale training job has been launched as of this update.

## Model and training contract

The canonical program-control OBJECTIVES.md defines one conditional biological model, not an annotation classifier: epigenomic context → transcriptional transition (H1) → translation efficiency (H2) → protein change (H3) → degradation/processing context → peptide–HLA presentation change (H4). State and perturbation condition a learned machinery bottleneck. H4 also needs detectability/censoring, abundance and perturbation direction; class-II register is supervised only where a register is actually observed. Durability, inflammation-conditional epitopes and other application scores are derived and calibrated from these outputs. Clinical-outcome training is not silently substituted for them.

All layers means the selected biological encoder, modality encoders, machinery bottleneck and supported heads participate in optimization. A frozen 4-bit language backbone with LoRA is not full-parameter training. The existing BioMate reasoning interface remains an existing LLM with evidence retrieval and biological model tools; it is not a newly invented reasoning LLM. Literature supports provenance-preserving retrieval and audited alignment examples; it is not treated as measured perturbation outcomes.

All data means no arbitrary per-study, target or cell cap. Preserve held-out data for evaluation, remove true duplicates, and record quality/legal/assay exclusions. Raw storage bytes are not unique cells or training examples. No silent substitution of assembled_v7_capT100_capVT800 for the complete corpus.

All knowledge means typed, source-attributed graph relations and signed regulatory/pathway/genetic priors, with the full gene/drug vocabulary reconciled. Graph claims must remain distinguishable from experimental labels. Do not collapse drug nodes into genes or treat literature assertions as independent validation.

All objectives means an explicit coverage ledger for H1–H4, detectability, register, masked modality reconstruction, cross-study hard negatives, perturbation invariance and knowledge constraints. Each objective requires eligible observations, valid masks, measured gradient activity and held-out metrics. A nonzero configured weight alone does not establish training. Staged dense-to-sparse curriculum is followed by joint replay to prevent forgetting; incompatible/unpaired assays do not receive invented paired losses.

## Implementation sequence

1. Freeze the uncapped S3 object inventory and provenance. Compile source roles and adapter readiness. Resolve accession/sample/barcode overlaps before donor/study/perturbation splits. Stream native matrices into bounded shards with stable feature IDs and feature-level observation masks; save every consumed/excluded count.
2. Repair shared model wiring. The staged knowledge2_joint change restores gradients from knowledge-mode outputs to the backbone and omics path. Preserve legacy checkpoint behavior under its original configuration. Replace annotation-proxy claims with the actual H1–H4 task contract. Reuse working components only where their semantics match.
3. Implement typed graph and source-specific modality adapters, perturbation/control pairing, HLA/sample alignment and censoring-aware peptide labels. Confirm H2 measured translation coverage explicitly; transcript abundance is not a translation-efficiency label.
4. Implement heterogeneous task scheduling and exact resumability: optimizer, scheduler, mixed-precision scaler, RNG, source/sampler position and schema/manifest identities. Save exposure counters and per-objective observed counts. Use distributed GPU training with bounded remote staging; do not load multi-terabyte sources into local RAM.
5. Run an integration preflight on real source shards that proves streaming, feature alignment, leakage boundaries, finite loss/gradients, checkpoint replay and validation output. This verifies infrastructure; it does not replace the full run or impose a pilot performance gate on source inclusion.
6. Package the exact reviewed source/config and select dedicated compute. Available regional quotas are 384 on-demand G/VT vCPUs, 96 P vCPUs and 768 G/VT Spot vCPUs; these are quota limits, not a capacity reservation. No idle GPU was found. Size the job from measured throughput/memory; include resume, checkpoint upload verification and shutdown on completion/failure. Do not use production instances.
7. Execute uncapped pretraining, knowledge/perturbation conditioning, H1–H3 joint training, sparse H4/censoring training and joint replay. Record trainable parameter counts, source coverage and objective exposure at every phase. Flag unsupported objectives instead of declaring them complete.
8. Evaluate held-out studies/donors/perturbations/alleles with no-change, linear, transcript-proportional and guide-shrinkage baselines as appropriate. Include null/shuffled controls, bottleneck/knowledge/modality ablations, leakage, calibration and domain-specific results. Previously examined test cohorts become development evidence. No production promotion based on training loss or synthetic wiring tests.

## Current verified state

- Live RNA source inventory: 2.152 TB base plus 270.438 GB expanded; other modalities and perturbations are separately enumerated in data_inventory.md. Overlap remains unresolved.
- Existing full-corpus launcher is capped RNA-only. It is not the requested full-scale run.
- Staged joint-path/observed-label implementation passes five focused tests; it is not a completed joint trainer and does not implement H1–H4 by itself.
- Previous 32-target neural pilots did not beat guide shrinkage and are development results, not foundation-model training.
- Remaining launch dependencies are actual corpus adapters/pairing, objective implementations, task scheduling, exact resume, real-data integration verification and a dedicated reviewed compute deployment.

## Evidence files

- architecture_inventory.md — implemented versus advertised architecture.
- data_inventory.md / data_inventory.json — live source groups and eligibility.
- s3_metadata_inventory.json — keys, bytes, ETags and timestamps; ETags are not assumed content hashes.
- wiring_implementation.md — staged fix, verification and limits.

The historical H4 mechanism-recovery PASS in OBJECTIVES.md is not evidence that a trained H4 model generalizes. The full-scale evaluation must establish that separately.

## Implementation checkpoint later on 2026-09-12

Training branch commits: 99b561172 (wiring, source manifest, measured losses, exact resume), 3c2951338 (conditional H1–H4 heads), 560a65940 (uncapped native-count sharding). Forty-three combined regression tests passed, plus five canonical-head tests and twelve shard-adapter tests. These are implementation tests, not a full-scale training evaluation.

The count adapter handles explicitly selected raw.X/layers/X, raw feature axes, CSR/CSC/dense matrices and constant or column-based study IDs. It preserves all rows/genes without a cell cap. A complete 565-cell source verified normalized-X rejection and raw-count conversion, but all its cells are marked non-primary; conversion does not establish training eligibility. Cross-source duplicate resolution and source-specific count provenance remain necessary.

The conditional heads now permit RNA/H1-only batches without fabricated protein/peptide inputs. Verified H4 loss gradients reach H3, H2, H1 and the machinery state. Register/detectability heads still require independent labels; computing their outputs is not training them. The joint trainer, source adapters beyond RNA, typed knowledge integration, global splits and remote launch remain unfinished.

Knowledge-source usage is separately audited in KNOWLEDGE_SOURCE_USAGE.md. The file called full MAP-KG is a gene/protein interaction view, not verified full heterogeneous knowledge. Existing OpenTargets response retrieval searches target descriptions rather than providing the requested disease/genetic evidence. These gaps are part of the remaining integration work.
