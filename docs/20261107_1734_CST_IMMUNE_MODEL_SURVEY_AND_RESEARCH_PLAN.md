# Immune representation models literature survey and research plan

Prepared 7 November 2026, 17:34 CST (America/Chicago).

## Purpose and scope

Identify recent single-omics, paired multiomics and spatial representation models that affect the novelty and experimental design of HybridImmuneLLM. Translate the findings into a research programme testing the incremental value of learned representations within the broader BioMate system.

This is a focused, primary-source-led survey through 7 November 2026, emphasizing Nature, Nature Methods, Nature Biotechnology and Nature Communications. It is not an exhaustive systematic review or a quantitative meta-analysis. Search results and accessible publisher text were reviewed; supplements, licenses, checkpoint availability and all benchmark protocols have not been fully audited. Some direct publisher requests failed, although indexed publisher text was available. Publication claims below are the authors' reports, not independently reproduced results. Numerical scores from different papers must not be compared as a leaderboard.

The system objective remains: learned representations augment specialist downstream methods and evidence-supported reasoning. A universal language model solving every objective is not the goal. Measured modalities, auxiliary biological priors and retrieved literature must be distinguished.

## Published models most relevant to the programme

| Model | Publication | Measurement or information type | Reported contribution | Implication for our experiments |
|---|---|---|---|---|
| UCE | Nature, online 8 July 2026 | Primarily cell transcriptomes, with protein-sequence-informed gene representations | Universal embeddings, zero-shot application to new datasets and cross-species analyses; a 36-million-cell integrated atlas is an application resource, not automatically the pretraining count | High-priority frozen representation comparator; audit overlap and gene mapping |
| CellFM | Nature Communications, 20 May 2025 | Single-cell transcriptomics | Pretraining on 100 million human cells | Corpus size alone is not a distinctive contribution; consider as a scale comparator after access and resource checks |
| scLong | Nature Communications, 5 February 2026 | Single-cell transcriptomics | Billion-parameter model targeting long-range gene context | Relevant to restricted input vocabularies; optional resource-intensive comparator |
| CAPTAIN | Nature Communications, 7 May 2026 | Co-assayed RNA and surface protein | Reports more than four million cells and a repertoire of 382 surface proteins; cross-modal prediction, annotation and integration | Most direct new RNA–protein comparator; determine precisely which measurements are required at training and inference |
| Nicheformer | Nature Methods, 2025 | Dissociated and spatial transcriptomics | Representations trained across dissociated and spatial assays, with spatial-context evaluations | Relevant when tissue context is available; multiple assays of RNA are not equivalent to multiple molecular omics |
| OmiCLIP | Nature Methods, 2025 | Histology and spatial transcriptomics | Visual–omics alignment using more than 2.2 million paired observations from 113 studies | Candidate specialist image–molecular component; preserve spot, cell and patient distinctions |
| VirTues | Nature, online 5 August 2026 | Spatial proteomics, with protein-language-model marker identities | Variable-panel representations at cell, niche and tissue scales; core 15-cohort resource and broader multi-technology analyses; downstream biomarker applications | Architectural precedent for marker identity and hierarchical aggregation; clinical findings are not prospective utility validation |
| GET | Nature, 8 January 2025 | Regulatory information across human cell types | Foundation model of transcriptional regulation | Candidate conceptual precedent for a specialist regulatory module, rather than indiscriminate feature fusion |
| scGPT | Nature Methods, 2024 | Transcriptomic pretraining with multiomic applications | Generative cell representation framework | Retain as an established baseline; separate pretraining inputs from downstream multimodal capabilities |
| scFoundation | Nature Methods, 2024 | Single-cell transcriptomics | 100-million-parameter model covering about 20,000 genes, pretrained on more than 50 million profiles | Useful broader-vocabulary reference; baseline selection should follow task and compute feasibility |

### Primary source links

1. UCE, *Universal cell embedding provides a foundation model for cell biology*: https://www.nature.com/articles/s41586-026-10689-z
2. CellFM, *CellFM: a large-scale foundation model pre-trained on transcriptomics of 100 million human cells*: https://www.nature.com/articles/s41467-025-59926-5
3. scLong, *scLong: a billion-parameter foundation model for capturing long-range gene context in single-cell transcriptomics*: https://www.nature.com/articles/s41467-026-69102-y
4. CAPTAIN, *CAPTAIN: a multimodal foundation model pretrained on co-assayed single-cell RNA and protein*: https://www.nature.com/articles/s41467-026-72882-y
5. Nicheformer, *Nicheformer: a foundation model for single-cell and spatial omics*: https://www.nature.com/articles/s41592-025-02814-z
6. OmiCLIP, *A visual–omics foundation model to bridge histopathology with spatial transcriptomics*: https://www.nature.com/articles/s41592-025-02707-1
7. VirTues, *The Virtual Tissues foundation model resolves spatial proteomics across scales*: https://www.nature.com/articles/s41586-026-10884-y
8. GET, *A foundation model of transcription across human cell types*: https://www.nature.com/articles/s41586-024-08391-z
9. scGPT: https://www.nature.com/articles/s41592-024-02201-0
10. scFoundation, *Large-scale foundation model on single-cell transcriptomics*: https://www.nature.com/articles/s41592-024-02305-7

## Evaluation literature changes the interpretation of negative results

The 2025 Nature Methods paper *Deep-learning-based gene perturbation effect prediction does not yet outperform simple linear baselines* makes strong simple baselines essential:
https://www.nature.com/articles/s41592-025-02772-6

The October 2026 Nature Biotechnology paper *Deep learning perturbation models can outperform baselines on calibrated metrics* examines 14 datasets and 18 metrics and reports that common measures can obscure perturbation-specific signal. Positive-control calibration can change conclusions. This does not establish universal superiority over strong linear models, nor does it validate our model:
https://www.nature.com/articles/s41587-026-03307-w

Our evaluation must therefore satisfy both requirements: strong task-matched baselines and metrics demonstrated to discriminate a positive control from an uninformative prediction. Repeated biological measurements should establish signal quality and attainable performance. Metric selection must be declared before inspecting model rankings.

## Perspectives and preprints are separate evidence classes

The Nature perspective *Towards multimodal foundation models in molecular cell biology* provides a research direction, not an independently benchmarked model:
https://www.nature.com/articles/s41586-025-08710-y

A Cell article *A world model of the virtual cell* provides a broader formulation of evolving cellular state and intervention. It should not be counted as proof that a general-purpose cellular simulator has been achieved:
https://www.sciencedirect.com/science/article/pii/S0092867426010159

Recent preprints identified for follow-up include CellxPert (https://arxiv.org/abs/2605.00930), scAnyOmics (https://arxiv.org/abs/2610.41399) and a harmonised foundation-model benchmark (https://arxiv.org/abs/2607.17227). These are watch-list entries from the search, not fully reviewed, journal-validated baselines. Verify versions, artifacts and methods before adoption.

## Strategic assessment

Interpretation: neither model scale, a large RNA corpus, nor architectural support for several modalities is sufficient novelty in this landscape. Our current evidence is more persuasive as task-dependent representation transfer than as a general virtual-cell breakthrough.

The proposed central question is: **When does immune-state pretraining provide information that improves downstream prediction beyond measured expression, established representations and curated knowledge?**

A promising focused application is predicting an immune perturbation's functional effect in a new donor or activation state. Interferon signalling and antigen presentation are candidate domains, pending an audit of independent datasets and usable endpoint labels. Classifying perturbation identity is not equivalent to predicting a perturbation-induced response.

## System architecture and evidence boundaries

Measured omics feed reusable representations. Specialist task models use those representations alongside task-appropriate observations. BioMate combines the resulting predictions with traceable KG/RAG evidence to generate findings and explanations.

- RNA, protein, chromatin and spatial inputs need assay-appropriate encoders and measured-feature masks.
- Molecular features, cell states, tissue niches and patient outcomes have different observational units.
- Knowledge-derived features need explicit provenance; they are not another measured omics assay.
- Retrieval supplies evidence, context and contradictions. Its contribution to explanation quality is evaluated separately from prediction accuracy.
- Target prioritization needs temporal and label-overlap audits so curated evidence does not leak target labels into evaluation.
- Treatment duration requires longitudinal treatment/exposure endpoints. Overall or progression-free survival is not a substitute.
- No architectural component earns a scientific contribution merely because it is present or receives a gradient.

## Execution plan and decision gates

### Stage 0 — Freeze provenance and repair evaluation validity

Create an immutable manifest for each experiment: source accession and version, unique sample/cell IDs, donor/study/cohort IDs, modality pairing, label definitions, exclusions, split memberships, preprocessing fit population, gene and antibody mappings, checkpoint hash/configuration, seed and environment.

Resolve manuscript counts and changing raw-gene baselines. Preserve old results as historical artifacts; corrected evaluations get new namespaces. Audit pretraining overlap for our checkpoints and each external model. Label unknown overlap explicitly rather than claiming strict zero-shot evaluation.

Deliverables: dataset/checkpoint manifest, reproducible split files, audit ledger, corrected preprocessing tests.

Gate: no unexplained cross-split donor overlap, preprocessing fitted on held-out inputs, silently missing required checkpoint tensors, or untracked dataset substitutions.

### Stage 1 — Matched representation transfer

Core arms: raw-expression classifier, train-fitted PCA, scVI, our frozen representation, UCE and scGPT. Add an appropriate Geneformer checkpoint with a valid-vocabulary sensitivity analysis. CAPTAIN belongs in the paired-data comparisons where its interface is compatible. Add CellFM/scFoundation/scLong only after resource and artifact assessment.

Use each pretrained model's documented input processing. Report both native-input and common-feature controls where feasible; forcing every model into a 2,000-gene panel is not automatically fair. Freeze dataset identities, labels, splits, downstream estimators and tuning budgets. Keep transductive integration separate from inductive transfer.

Primary endpoint: study-level annotation macro-F1, with paired differences and uncertainty resampling studies. Report fine-grained labels, study predictability within cell type, computational cost and failures.

Few-shot protocol: draw 4, 16, 64 and 256 labelled cells per class within each held-out study, using identical adaptation/query IDs across feature sets. Define eligibility and rare-class handling before running; report excluded studies/classes. Fit scaling on adaptation cells. Include donor-disjoint adaptation as a distinct harder protocol when donor metadata allow it. Use multiple draws; do not treat repeated draws as independent studies.

Gate: the label-budget crossover must replicate across independent studies, not only pooled cells. Report heterogeneity even if the aggregate difference is positive.

### Stage 2 — Transferable multimodal value

Arms: RNA only; protein only; simple concatenation/regularized model; our fusion from scratch; pretrained fusion; compatible CAPTAIN outputs. Hold out studies and evaluate panel shift explicitly. Distinguish an assay feature absent from the panel from a measured zero.

Architectural experiment: marker identities represented by learned identifiers or sequence-derived features, compared with fixed slots and shared-panel baselines. VirTues motivates this design but does not prove it will work for CITE-seq.

Primary endpoint: a prespecified immune functional-state endpoint, using AUROC and AUPRC with uncertainty at the relevant donor/study/perturbation unit. Imputation is a secondary endpoint, scored against actual measured values in held-out groups. Include shuffled modality alignment and controlled feature masking as diagnostic controls.

Gate: a reproducible incremental gain over the strongest simple multimodal control. Determine whether gain comes from extra measurements, pretraining or architecture through separate ablations.

### Stage 3 — Perturbation effects with calibrated evaluation

Predict effects of unseen perturbations, unseen donors and unseen activation contexts in separate experiments. Attempt joint holdouts only when data support them. Primary biological endpoints should describe changes in functional programmes or differential expression; define control populations explicitly.

Baselines: control mean, mean perturbation response, linear prediction and a relevant specialist model. For combination tasks include an additive baseline. Use replicate-derived positive controls, shuffled perturbation identities and retrieval metrics with correct tie treatment. Define any DEG selection/weighting using an explicit protocol that does not influence model fitting through held-out labels.

Gate: positive controls must separate from nulls; if they do not, diagnose low signal or metric failure before interpreting model differences. Replicate gains on independent biological units and an external dataset where feasible.

### Stage 4 — Downstream system contribution and external confirmation

Factorial comparison: specialist method alone; plus learned representation; plus curated knowledge; plus both. Match tuning and input availability. Evaluate whether KG/RAG improves traceability and factual support separately from whether encoded knowledge improves prediction.

Select one biological claim for independent validation. For prospective work, define success, negative controls and assay endpoints before experiments. Clinical deployment and improved therapy selection are not claims supported by retrospective representation scores alone.

Gate: meaningful incremental utility over expression and knowledge alone, with calibrated uncertainty and external confirmation appropriate to the claim.

## Priority and resource policy

Immediate order: provenance and preprocessing repair; matched UCE comparison; compatible CAPTAIN comparison; per-study label-budget experiment; one functional perturbation endpoint. Reuse frozen checkpoints first. Establish end-to-end correctness on a small diagnostic subset before expensive inference or training. Measure runtime and memory before selecting the full run budget. This plan does not assert GPU availability or start new paid instances.

Do not add objectives or scale training merely to increase breadth. Extend protein identity encoding, chromatin mechanisms or spatial aggregation when measured failure modes justify them. Numerical go/no-go effect thresholds should be selected from endpoint relevance and achievable sample size before test-set results are viewed, not invented after observing a gain.

## Initial implementation audit on 7 November 2026

Read-only audit of `/Users/kky/biomate-audit-fix`, branch `audit-fix-immune-llm`, HEAD `4b6692e32`. Files may contain uncommitted work, so HEAD alone is not a complete reproducibility identifier.

1. **Confirmed preprocessing exposure.** `research/immune_llm_baseline/finetune_pretrained_vs_scratch.py` calls `zscore` in both data loaders; it estimates mean/std over the loaded dataset before `GroupKFold`. Protein standardisation also precedes fold construction. This is held-out-feature exposure, not demonstrated label leakage. Correct it and rerun before claiming strictly inductive transfer. For low-label experiments explicitly decide whether preprocessing may use all unlabelled training-fold cells or only labelled adaptation cells.
2. **Confirmed pooled adaptation.** `fewshot_baselines_capped.py` calls `fewshot(X, yte, k, seed)` across the pooled test set; the sampler takes no study identifier. It does not estimate per-study adaptation. Preserve this result with its narrower interpretation and implement the separate study-aware experiment.
3. **Existing calibration code.** `calibrated_metrics.py` already implements weighted errors/correlation, retrieval ranking and dynamic-range normalization. Review its formulas and provenance against the final publication rather than introducing a duplicate implementation. Its header attribution differs from the publisher metadata found in the survey and needs reconciliation.
4. **Confirmed tie behavior.** The retrieval function `nir` counts strictly smaller distances. If all candidate distances tie, every candidate receives a score of 1.0. This rewards uninformative predictions in that edge case. Specify tie-aware ranking and test it, including degenerate banks and finite-input checks, before using the metric as evidence.
5. **Checkpoint validation weakness.** Fine-tuning loads with `strict=False` and then filters missing keys to those present in the supplied state dictionary. This does not adequately reject missing required encoder parameters. Establish an explicit allowed-missing set for intentionally excluded heads/buffers and fail on other missing/unexpected/shape-mismatched parameters.
6. **Existing baseline registry.** `benchmark_registry.json` supplies task/dataset scaffolding. Reconcile rather than replace it; literature numbers must remain separate from results measured on our exact splits.
7. **UCE integration scaffold exists.** BioMate contains generated `get_uce_embeddings_scRNA` workflow wrappers. This is evidence of an integration entry point, not proof of a working, matched immune benchmark or locally available weights.

No model training, checkpoint download, corrected biological evaluation or external reproduction was performed for this documentation task. The code findings above are static inspection findings. The next implementation batch should repair and test the evaluation contracts before generating new comparative results.

## Completion criteria for the next manuscript revision

The stronger paper should provide a reproducible matched evaluation, an independently replicated account of where label scarcity makes pretraining useful, an ablation establishing the contribution of measured additional modalities, and at least one substantive downstream biological task. If those gains do not materialize, report the resulting boundaries honestly rather than widening claims. Journal selection should follow the strength and generality of the evidence.
