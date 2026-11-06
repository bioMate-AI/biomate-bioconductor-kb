# SYSUCC data linked drug development showcases

Date: 2026-10-29

SYSUCC's most valuable contribution to BioMate is the connection between tumor context, experimental models and measured treatment or assay outcomes. These can produce hospital-specific target evidence, functional labels, adapted models and independent benchmarks across drug-development stages. A patient record is not a molecule-training label, and a stored specimen is not yet an analysis-ready dataset.

This catalogue separates publicly documented resources from potential collaboration inputs. It is not an inventory of data the hospital has agreed to supply, nor a claim that every showcase is already deployed. Multicenter studies and partner-owned assays require their own access and reuse decisions.

## Publicly documented assets

| Asset family | Evidence | What to request or confirm |
| --- | --- | --- |
| CRC genomic and clinical cohort | The [ChangKang study, Nature Communications 2022](https://www.nature.com/articles/s41467-022-30062-8) reports tumor/matched-normal exomes from 1,015 Chinese CRC patients and clinical annotations. Processed genomic resources and clinical supplement are described in the paper. Raw reads HRA000873 are restricted, with academic/non-profit consent conditions. | Current processed files, dictionaries, permitted demonstration/commercial-research use and which follow-up fields can be reused. Public visibility does not clear the raw reads for BioMate. |
| Biobank and linked specimen records | The [official Tumor Bank page](https://english.sysucc.org.cn/index_31.aspx) describes blood, fresh tissue, marrow, biopsies, body fluids, tumor/adjacent-normal material and HIS-linked clinical information. | Current specimen inventory, donor/specimen linkage, consent/purpose flags, QC and availability of paired digital assays. The undated page's counts are not treated as a current census. |
| NPC single-cell and spatial immune data | A [2024 original study](https://www.nature.com/articles/s41467-024-52153-4) combines single-cell, immune-receptor and spatial data and identifies SYSUCC specimen cohorts. Some integrated cohorts are public/reused or multicenter. Processed records include GSE206245; raw HRA006885 access is controlled. | Exact institution-owned samples, cell annotations, batch/protocol metadata, treatment/outcome linkage and access to processed versus raw files. |
| Organoids and functional screening | The [2022 NPC organoid study](https://pubmed.ncbi.nlm.nih.gov/35928731/) documents a collaborative patient-derived organoid model/living biobank. A [2022 HER2-resistance study](https://www.nature.com/articles/s41467-022-30217-7) includes patient-derived resistance models and drug-response experiments. | Current viable models, completed dose-response and combination assays, controls, compound identifiers, raw plate/images and paired tumor data. Published use does not establish a centralized hospital-wide high-throughput screen database. |
| Pathology images and tissue markers | The NPC spatial study includes H&E and multiplex IHC. A [2022 EBV gastric-cancer study](https://www.nature.com/articles/s41467-022-30459-5) provides another disease-specific image/clinical research example. | Which slides are digitized, image formats, regions and pathologist annotations, stain/batch metadata and specimen links. A pathology archive is not automatically an approved training corpus. |
| Blood-based molecular biomarkers | The [MESA study, Genome Medicine 2024](https://link.springer.com/article/10.1186/s13073-023-01280-6) explicitly includes a SYSUCC CRC cohort for cfDNA methylation/fragmentation research; other study cohorts came from elsewhere. | Exact locally controlled samples, assay panels, timepoints, controls and permitted use. Longitudinal MRD data are a separate confirmation, not implied by this detection study. |
| Imaging, clinical treatment and outcomes | Published SYSUCC studies and its [2025 institutional AI report](https://www.sysu.edu.cn/news/info/2171/1390811.htm) establish substantial clinical/imaging data use. | Actual exports and linkage for MRI/CT/PET, treatment dates/doses, response assessments, recurrence, survival, laboratory tests and adverse events. Completeness and comparators must be assessed. |
| Trials, protocols and study documents | The [official Clinical Trials Center](https://english.sysucc.org.cn/index_28.aspx) and [JUPITER-02 original trial report](https://jamanetwork.com/journals/jama/fullarticle/2812324) establish clinical-research activity and available public study documentation. | Protocols/SAPs/SOPs and any permitted individual-level data. Sponsor-controlled and multicenter data cannot be assumed to belong solely to the hospital. |

Proteomics, phosphoproteomics, metabolomics, microbiome, functional screens and specialized immune data should be requested program by program. Publication affiliation alone is insufficient to establish a reusable institutional collection.

## Contributions to the platform

1. **Contextual evidence:** target prevalence, cell type, tumor subtype, disease stage and resistance context beyond general public associations.
2. **Functional labels:** measured binding, cellular effects, organoid response, selectivity and failures. These are especially important for surrogate and generator learning.
3. **Reference representations:** hospital-specific tumor/immune cell states, spatial niches, pathology phenotypes and assay ontologies.
4. **Adapted models:** private predictors, molecular/peptide generators or cell-response models where the input representation and supervision match the task.
5. **Independent benchmarks:** held-out hospital cohorts, assay batches, sequence families and chemical scaffolds to test generalization rather than merely fit local examples.
6. **Reusable research practice:** verified SOPs, parameter templates, analysis workflows, report conventions and expert corrections.

These may remain private hospital assets. Contribution does not imply permission to pool patient data, redistribute proprietary chemistry or update a global BioMate model. Dataset, model and co-generated-result rights need an explicit agreement.

## Stage 1 Disease understanding and target discovery

| Showcase | Hospital inputs | BioMate workflow and additional asset |
| --- | --- | --- |
| 1. Find underserved molecular subgroups | Diagnosis/stage, prior treatment, recurrence and outcomes | Cohort characterization identifies research priorities; builds an institution-specific disease/subgroup evidence map. Observational differences do not establish causal treatment benefit. |
| 2. Prioritize cohort-specific targets | Mutation/CNV, tumor/normal expression, proteomic or validated score tables | Combine local evidence with public target associations; produce a shortlist with explicit criteria and conflicting evidence. Local score tables require a defined meaning and normalization. |
| 3. Locate targets in the correct cells | scRNA-seq/h5ad, cell identities and normal comparators | Separate malignant, stromal and immune expression; create cell-specific target and potential liability annotations. Expression alone is not proof of target dependency. |
| 4. Identify spatial niches and accessible interfaces | Spatial transcriptomics, H&E/IHC, region annotations | Map tumor–stroma/immune interactions; generate hypotheses for peptide-accessible surface interactions and combinations. Colocalization or ligand–receptor inference is not causal validation. |
| 5. Validate dependencies with perturbations | CRISPR guide-count tables, Perturb-seq or other functional readouts | Compare functional effects with target nominations; build causal-support evidence and resistance hypotheses. These data must be confirmed rather than assumed present. |
| 6. Study immune response and escape | Expression, immune receptor data, matched pretreatment tissue and outcomes | Score immune signatures, compare subgroups and nominate immune mechanisms. A treatment-only responder association is not a validated predictive treatment-benefit biomarker. |
| 7. Discover resistance mechanisms | Paired baseline/progression omics and relevant experimental models | Separate acquired alterations and cell states; propose resistance-directed target, small-molecule or combination experiments. |
| 8. Build virtual-cell and immune-model references | Annotated tumor/immune cells; perturbation-labelled data for response training | Adapt representations and benchmark predicted cell-state changes. Untreated scRNA data support references but do not alone supervise intervention response. |

## Stage 2 Hit discovery and modality selection

| Showcase | Hospital or authorized partner inputs | BioMate workflow and additional asset |
| --- | --- | --- |
| 9. Select small-molecule hits | Compound IDs, SMILES/SDF, target structure and measured assay results | Search/evaluate compounds against the local target context; build a task-specific activity model and a traceable shortlist. Docking is a computational evaluation, not a measured binding label. |
| 10. Investigate drug repurposing | Tumor signatures, functional screens and drug evidence | Match mechanisms and experimental responses to existing compounds; produce testable repurposing hypotheses with orthogonal validation plans. |
| 11. Design resistance-directed molecules | Mutant sequences/structures, matched biochemical/cellular assays | Compare correctly specified mutant and reference targets; learn local structure–activity relationships. Mutation prevalence does not by itself prove drug sensitivity. |
| 12. Generate cyclic-peptide candidates | Target interface, exact sequence/chemistry, binding/functional measurements | Condition generation and evaluate candidates for αvβ6, PD-L1 or a hospital-selected target. The exact chemistry representation and approximation limits must accompany the output. |
| 13. Select the appropriate therapeutic modality | Target location, normal-tissue expression, interface evidence and experimental tractability | Compare small molecule, cyclic peptide and other appropriate research approaches. Produces a reasoned modality decision rather than forcing every target into one generator. |
| 14. Explore antigen-specific peptide or immune research | HLA type, tumor variants, immunopeptidomics and validated TCR/antigen data | Generate neoantigen/immune hypotheses and experimental priorities. This is an optional expansion requiring those datasets, specialized workflows and validation; no personalized vaccine or cell-therapy readiness is implied. |

## Stage 3 Lead optimization and experimental learning

| Showcase | Hospital or partner inputs | BioMate workflow and additional asset |
| --- | --- | --- |
| 15. Learn from real dose-response curves | Concentrations, replicates, plate controls, cell/organoid IDs and compound/peptide identity | Fit/review curves and uncertainty; create compatible potency/response labels rather than train on unverified single summary scores. |
| 16. Run an active-learning cycle | Completed assay batches including negative results and failed candidates | Ingest results, update a surrogate and propose the next diverse batch. Builds a measured experimental learning loop; simulated feedback only tests mechanics. |
| 17. Optimize peptide developability | Binding, selectivity, solubility, stability, proteolysis and relevant permeability assays | Learn chemistry-specific property relationships and multiobjective tradeoffs. Cell permeability need not be the main objective for an extracellular target. |
| 18. Investigate combinations and schedules | Drug-pair concentration matrices, time/schedule, model identities and controls | Analyze interaction under a stated reference model; choose follow-up experiments. Two good single-agent scores are not evidence of synergy. |
| 19. Evaluate selectivity and normal-tissue liabilities | Counter-target binding, matched normal organoid/cell assays and toxicity readouts | Identify therapeutic-window hypotheses and candidates needing rejection or further tests. Normal-tissue expression is a prior, not a toxicity assay. |
| 20. Model donor and subtype variation | Multiple molecularly annotated PDO/PDX/cell models and replicated treatment readouts | Estimate where an effect generalizes or fails; create context-aware response models and independent validation sets. Do not use this as clinical treatment selection. |

## Stage 4 Preclinical and translational development

| Showcase | Hospital or partner inputs | BioMate workflow and additional asset |
| --- | --- | --- |
| 21. Calibrate ADMET and exposure models | Measured permeability, microsomal stability, protein binding, hERG and concentration-time data | Compare predictions with observations and update endpoint-specific models. A broad archive of these assays has not been confirmed at SYSUCC. |
| 22. Connect candidate effects to mechanism | Treated/untreated transcriptomics, proteomics, perturbations and functional phenotypes | Evaluate pathway engagement, off-target hypotheses and escape responses; compare model-predicted versus measured changes. |
| 23. Derive pathology research phenotypes | WSI/IHC/multiplex images, annotations and linked molecular/assay records | Quantify validated image features and investigate relationships with drug response. Existing BioMate WSI/IHC execution is narrower than a diagnostic pathology platform. |
| 24. Develop pharmacodynamic biomarker hypotheses | Serial biopsies, molecular assays, imaging and exposure | Ask whether the intended biology changes after treatment and whether that tracks outcome. Pharmacodynamic change and validated surrogate endpoints are different claims. |
| 25. Study longitudinal liquid-biopsy signals | Serial ctDNA/EBV DNA/methylation with timing and outcomes | Explore response, resistance and recurrence trajectories. These longitudinal datasets must be confirmed; a cross-sectional early-detection cohort does not establish them. |
| 26. Validate outside the training setting | Independent hospital/time/cohort/assay and chemistry-family holdouts | Evaluate transportability, calibration and failure modes; create credible local benchmarks and update-promotion criteria. |

## Stage 5 Clinical development and later research

These are research uses requiring study-specific implementation and qualified review, not autonomous clinical decisions.

| Showcase | Permitted inputs | BioMate workflow and additional asset |
| --- | --- | --- |
| 27. Estimate trial feasibility and biomarker prevalence | Protocol criteria and appropriately coded institutional cohorts | Count potential research cohorts and missing fields; inform investigator planning. The specific patient-enrichment workflow is a stub, not a turnkey cohort query. This does not negate existing biomarker-interaction or pharmacology workflows. |
| 28. Analyze dose/exposure-response research | Trial-grade dose, timing, PK, PD, efficacy and safety | Existing PKNCA, nlmixr2 and exposure-response sources support prespecified analyses. Qualify the chosen input/output contract and current execution with clinical pharmacology oversight; no autonomous dose recommendation. |
| 29. Analyze efficacy and biomarker interactions | Trial/control assignments, endpoints, censoring and baseline covariates | Real Gate3 interaction code supports qualified binary/continuous biomarker–treatment analysis; verify confidence-level handling. Preserve randomization and study populations. The workflow named survival_analysis_km is parametric simulation, not a patient-level survival-data analyzer. |
| 30. Explore real-world effectiveness and resistance | Longitudinal treatment, progression, molecular profiles and comparator information | Define research cohorts and test hypotheses with explicit confounding/selection limitations; not proof of efficacy from uncontrolled records. |
| 31. Study safety signals | Medication exposure, labs, adverse events, concomitant treatments and coding | Generate toxicity signals for clinical review. Private longitudinal analysis requires more than the existing public OpenFDA connector. |
| 32. Feed post-treatment findings back into discovery | Progression biopsies, resistance assays and clinical context | Update target priorities and propose a new experimental campaign, closing the research cycle without turning an association into a treatment recommendation. |

## Cross stage institutional showcases

| Showcase | New institutional asset |
| --- | --- |
| 33. Adapt private molecular/peptide models | Actual versioned weights/checkpoints trained from compatible authorized structures/sequences and measurements; evaluated on untouched holdouts. |
| 34. Adapt cell/immune/pathology representations | Task-appropriate reference embeddings or model updates, with donor/time/cohort separation and external validation. New training labels and runtime integration may be needed. |
| 35. Build a governed research knowledge workspace | Source-linked internal SOPs, papers, protocols, analysis results and corrections; instruction/retrieval adaptation is labelled separately from weight training. |
| 36. Produce reproducible scientific outputs | Evidence-linked reports, manuscript sections and publication figure/slide bundles with source data, run and model provenance. The publication packages still need their own completion and visual/scientific validation. |

## Current BioMate foundations and readiness boundaries

The [expanded capability review and comparison protocol](20261029_SYSUCC_PLATFORM_ALIGNMENT_AND_MODEL_COMPARISON.md) supersedes a narrow interpretation of this catalogue: BioMate already includes cited scientific-method/parameter guidance, campaign assay intake and multiobjective proposals, NCA/PopPK/PBPK/exposure-response, xenograft TGI, safety and formulation sources, and study-report/evidence assembly. Hospital data can extend all these layers. Formulation/delivery and biologics developability are additional partner-data-dependent showcases, not mandatory additions to the main small-molecule/peptide demo.

The existing target system can consume real score tables and public disease associations. Bulk RNA, single-cell, spatial, CRISPR, drug-discovery, docking, ADMET and pharmacology workflow sources provide useful starting points. The clinical arm contains genuine immune-signature analyses. WSI/IHC have documented real execution in the October 14 pathology validation record. These are meaningful foundations, but do not make every cross-modal hospital-data chain automatically demo-ready.

Genuine research training/checkpoint paths exist for cyclic-peptide models, and REINVENT training adapters and lightweight predictor training exist. The generic Chemprop training skeleton and simulated regulatory post_train_lora worker are not substitutes for these. Fix missing-metric quality gates, split contracts, durable model reload and ownership checks before claiming evaluated institutional model promotion. Do not describe an unrun virtual-cell GPU adapter or a catalogue entry as a validated hospital application.

## Recommended four showcases

**First, their own CRC evidence.** Begin with permitted processed ChangKang data: molecular subgroup → target prevalence/evidence → drug-development hypothesis → independent validation plan. This is more hospital-specific than starting solely from a generic public target query. Confirm access and reuse terms before ingesting any files.

**Second, NPC spatial and immune biology.** Show a tumor/immune/stromal niche, its candidate surface interaction and a peptide-oriented experimental hypothesis. Preserve the difference between their published findings and a newly generated hypothesis. Validate selected targets with the hospital scientists rather than prespecify one from a generic ranking.

**Third, the strongest learning loop.** Use an existing PDO/PDX or cell-assay program with compound identities and real concentration-response measurements. Import a new batch, create a new predictor version, evaluate it on unchanged held-out models/chemistry and propose the next experiment. If no authorized assay dataset is available, use a clearly labelled public proxy and keep the hospital-specific integration as the pilot step.

**Fourth, actual peptide weight adaptation.** Show an authentic completed model update with sequence/chemistry-compatible experimental or explicitly labelled proxy-property labels, optimizer/checkpoint evidence and independent evaluation. A permeability-property update is not proof of binding improvement or clinical efficacy. Do not claim that ordinary clinical records alone fine-tune the molecule generator.

## Minimum information to request from the hospital

Ask for a data catalogue and representative schemas first, not a bulk patient-data export:

- Dataset/study owner, permitted purpose, access process, publication/partner restrictions and retention conditions.
- Disease, subtype, stage, cohort size, sampling times and longitudinal follow-up completeness.
- Linkage between patient, specimen, cell/organoid/PDX, assay, treatment, image and outcome; identifiers can remain controlled within the hospital.
- Omics/image formats, QC, batch/scanner/platform details and annotation provenance.
- Compound structures or exact peptide chemistry, assay endpoint/units, concentrations, replicates, controls and failed/negative observations.
- Existing training and untouched test sets; overlap with public data, chemical/sequence families, donors and prior training corpora.
- Which systems can expose approved read-only interfaces, where inference/training may run, and which external searches or services are permitted.

The decisive collaboration asset is the **paired, well-annotated experimental record linked to tumor context**. It turns general software capabilities into locally evaluated research models and a real design–test–learn process. No SYSUCC data was downloaded, requested from staff or ingested into BioMate during this assessment.
