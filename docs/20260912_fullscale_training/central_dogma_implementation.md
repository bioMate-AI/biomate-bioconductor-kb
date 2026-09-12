# Canonical conditional heads, staged 2026-09-12

Read source of truth `/Users/kky/biomate-immune-llm/docs/program_control/OBJECTIVES.md` before implementation. This module addresses the requested conditional H1–H4 architecture, not a complete trained system or validated mechanistic claim.

`CentralDogmaHeads` consumes shared z_cell plus explicit perturbation features, computes machinery state, and predicts H1 transcription delta → H2 translation efficiency → H3 protein delta. H3 actually consumes H2 and H1 values selected through an explicit protein-to-transcript mapping. H4 consumes peptide and HLA features, machinery state, predicted source-protein delta and source-protein log abundance derived from a measured baseline. H4 has separate paired-delta, absolute abundance likelihood parameters and class-II register outputs. Detectability uses peptide sequence features only; it is separate from non-detection and does not generate abundance negatives.

All output scales must be recorded in the adapter/run schema. H3 is a log-protein-abundance delta on exactly the same scale as baseline_protein_log_abundance. H2 is supervised only against measured translation-efficiency labels, never RNA-derived placeholders. H4 log abundance supports the existing censored-normal likelihood through `central_dogma_losses`; missing entries require explicit observation/censoring metadata there.

`measured_losses` calls existing canonical task_loss and rejects missing scheduled labels. It does not create labels. Loss weights are explicit positive values. No clinical endpoint or annotation proxy is implemented.

Shared pointwise gene/protein decoders use embeddings and machinery features, avoiding dense all-gene G×G matrices. Parameter count grows linearly with gene/protein features; intermediate memory still grows with batch×feature count×hidden dimension. The parent can shard queries or reduce batch size for full dimensions.

Five tests passed using the current training-repo losses: H4 delta backward reaches every upstream head and z_cell/perturbation inputs; perturbation affects H1–H4; HLA affects H4 but not detectability; shapes, mappings and nonfinite observed input handling are checked. These use synthetic tensors strictly for implementation testing, not scientific evaluation.

Limits before claiming full training:
- No data adapters or corpus training implemented here. RNA-only/H1 batches require only z_cell and perturbation: H1/H2/H3 outputs are computed without measured protein baseline. H4 runs only when all four explicit contexts are supplied; partial H4 context is rejected. Computing an unsupervised head is not training it: H1-only backward does not update H2/H3. A dedicated regression test covers this. H4 remains restricted to verified baseline-protein/peptide/HLA/source availability.
- One transcript index per protein is an explicit simplification; isoform/protein-group ambiguity must be resolved or rejected by adapter, not silently guessed.
- Learned feature embeddings require immutable feature order and checkpoint schema identity.
- z_cell knowledge constraints, hard-negative contrastive, IRM, modality reconstruction and curriculum scheduler remain external; this module alone does not satisfy the entire canonical objective.
- Interpretable machinery constraints and explicit degradation measurements are not implemented; presentation_context learns conditional machinery dependence without a separately supervised degradative claim.
- Detectability, register and absolute abundance heads require their own real observations to train; H4-only loss does not train these independent outputs.
- Held-out perturbation/allele/study evaluation and all canonical baseline/linear-advantage gates remain necessary. Architecture connectivity is not evidence that the central-dogma predictions are correct.
