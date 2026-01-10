# SGI-Bench Life Science Test Examples: Comprehensive Documentation

## Executive Summary

This document provides detailed documentation of all life science-related test cases in SGI-Bench, including complete task specifications, action pools, evaluation criteria, and ground truth answers. These examples are directly relevant to BioMate AI's platform development for LC-MS data analysis and clinical applications.

---

## 1. Life Science Research Directions in SGI-Bench

SGI-Bench covers the following life science research directions inspired by Science's 125 Big Questions:

| Research Direction | Description | Relevance to BioMate |
|-------------------|-------------|---------------------|
| **Disease Biomarker Discovery** | Identifying molecular markers for disease diagnosis | Direct application for clinical metabolomics |
| **Tumor Neoantigen Discovery** | Cancer-specific antigen identification | Cancer biomarker workflows |
| **Tumor Immunotherapy** | Immune checkpoint inhibitor studies | PD-L1/PD-1 pathway analysis |
| **Protein Structure** | Structural biology and folding | Proteomics workflows |
| **Genome Function Prediction** | Functional genomics | Multi-omics integration |
| **AI Drug Discovery** | Computational drug design | ADMET prediction, compound screening |
| **Regulatory Element Design** | Gene regulatory network analysis | Synthetic biology workflows |

---

## 2. Wet Experiment: Anti-PD-L1 Immunotherapy Protocol

### 2.1 Background Context

Cancer development involves genetic and epigenetic alterations that enable tumor cells to evade immune detection by creating an immunosuppressive microenvironment. A key mechanism of immune evasion is mediated by the programmed death-ligand 1 (PD-L1), expressed on tumor and immune cells, which binds to programmed death-1 (PD-1) and B7.1 (CD80) receptors on T cells.

**Key Scientific Concepts:**
- PD-L1/PD-1 interaction inhibits T-cell migration, proliferation, and cytotoxic function
- Blocking PD-L1 can restore antitumor immunity by reactivating suppressed T cells
- Engineered humanized monoclonal antibody (MPDL3280A) targets PD-L1
- Fc domain modification prevents antibody-dependent cellular cytotoxicity

**Clinical Context:**
- Multiple cancer types: NSCLC, melanoma, renal cell carcinoma
- Biomarkers: PD-L1 expression on tumor-infiltrating immune cells
- Response predictors: TH1 gene expression, CTLA4 expression
- Progression marker: Fractalkine (CX3CL1) expression

### 2.2 Complete Action Pool (20 Atomic Actions)

```python
# ========== TISSUE PROCESSING ACTIONS ==========

<Fix_tissue_in_formalin>(tissue, fixative)
    Args:
        tissue: Tissue sample to be fixed
        fixative: Formalin solution
    Returns:
        Fixed tissue sample

<Embed_tissue_in_paraffin>(fixed_tissue)
    Args:
        fixed_tissue: Formalin-fixed tissue
    Returns:
        FFPE tissue block

<Section_tissue>(tissue_block, thickness)
    Args:
        tissue_block: Paraffin-embedded tissue block
        thickness: Section thickness in micrometers
    Returns:
        Tissue sections

# ========== IMMUNOHISTOCHEMISTRY ACTIONS ==========

<Stain_with_antibody>(tissue_section, antibody, concentration)
    Args:
        tissue_section: Tissue section on slide
        antibody: Primary antibody
        concentration: Antibody concentration
    Returns:
        Antibody-labeled tissue section

<Visualize_with_DAB>(stained_section)
    Args:
        stained_section: Antibody-stained section
    Returns:
        DAB-visualized section

<Counterstain_with_hematoxylin>(section)
    Args:
        section: DAB-stained section
    Returns:
        Counterstained section

<Score_IHC_staining>(stained_section, cell_type)
    Args:
        stained_section: Complete IHC-stained section
        cell_type: Type of cells to score (TC or IC)
    Returns:
        IHC score (0-3)

# ========== DUAL IMMUNOFLUORESCENCE ACTIONS ==========

<Incubate_with_primary_antibodies>(section, antibody1, antibody2, temperature)
    Args:
        section: FFPE tissue section
        antibody1: First primary antibody
        antibody2: Second primary antibody
        temperature: Incubation temperature
    Returns:
        Dual-antibody labeled section

<Detect_with_fluorescence>(labeled_section, detection_system, fluorophore)
    Args:
        labeled_section: Antibody-labeled section
        detection_system: Detection reagent system
        fluorophore: Fluorescent label
    Returns:
        Fluorescently labeled section

# ========== NUCLEIC ACID EXTRACTION ACTIONS ==========

<Extract_DNA_from_FFPE>(tissue_section, extraction_kit)
    Args:
        tissue_section: FFPE tissue section
        extraction_kit: DNA extraction kit
    Returns:
        Isolated DNA

<Extract_RNA_from_FFPE>(tissue_section, extraction_kit)
    Args:
        tissue_section: FFPE tissue section
        extraction_kit: RNA extraction kit
    Returns:
        Isolated RNA

<Perform_gene_expression_analysis>(RNA_sample, platform, gene_panel)
    Args:
        RNA_sample: Isolated RNA
        platform: Analysis platform
        gene_panel: Panel of genes to analyze
    Returns:
        Gene expression data

# ========== BLOOD SAMPLE PROCESSING ACTIONS ==========

<Collect_blood_sample>(patient, tube_type, volume)
    Args:
        patient: Patient identifier
        tube_type: Collection tube type
        volume: Sample volume
    Returns:
        Blood sample

<Isolate_plasma>(blood_sample, centrifuge_speed, time)
    Args:
        blood_sample: Whole blood sample
        centrifuge_speed: Centrifugation speed
        time: Centrifugation time
    Returns:
        Plasma sample

<Analyze_cytokines_by_ELISA>(plasma_sample, cytokine_panel)
    Args:
        plasma_sample: Isolated plasma
        cytokine_panel: Panel of cytokines to measure
    Returns:
        Cytokine levels

<Perform_FACS_analysis>(blood_sample, antibody_panel)
    Args:
        blood_sample: Blood sample
        antibody_panel: Panel of antibodies for staining
    Returns:
        Cell population data

# ========== TREATMENT AND MONITORING ACTIONS ==========

<Administer_MPDL3280A>(patient, dose, route)
    Args:
        patient: Patient identifier
        dose: Drug dose in mg/kg
        route: Administration route
    Returns:
        Treated patient

<Collect_tumor_biopsy>(patient, timepoint)
    Args:
        patient: Patient identifier
        timepoint: Collection timepoint
    Returns:
        Tumor biopsy sample

<Evaluate_tumor_response>(patient, imaging_method, criteria)
    Args:
        patient: Patient identifier
        imaging_method: Imaging modality
        criteria: Response evaluation criteria
    Returns:
        Tumor response assessment

<Store_sample>(sample, temperature)
    Args:
        sample: Biological sample
        temperature: Storage temperature
    Returns:
        Stored sample
```

### 2.3 Ground Truth Workflow Sequence

```
Step 1:  Administer_MPDL3280A
Step 2:  Collect_tumor_biopsy
Step 3:  Fix_tissue_in_formalin
Step 4:  Embed_tissue_in_paraffin
Step 5:  Section_tissue
Step 6:  Stain_with_antibody
Step 7:  Visualize_with_DAB
Step 8:  Counterstain_with_hematoxylin
Step 9:  Score_IHC_staining (cell_type=TC)
Step 10: Score_IHC_staining (cell_type=IC)
Step 11: Incubate_with_primary_antibodies
Step 12: Detect_with_fluorescence
Step 13: Extract_DNA_from_FFPE
Step 14: Extract_RNA_from_FFPE
Step 15: Store_sample (DNA)
Step 16: Store_sample (RNA)
Step 17: Perform_gene_expression_analysis
```

### 2.4 Key Biomarkers Assessed

| Biomarker | Type | Significance |
|-----------|------|--------------|
| PD-L1 on TC | IHC Score | Tumor cell expression |
| PD-L1 on IC | IHC Score | Immune cell infiltration |
| TH1 signature | Gene Expression | Response prediction |
| CTLA4 | Gene Expression | Immune activation |
| CD8+ T cells | Flow Cytometry | Effector cell quantification |
| IFN-γ | ELISA/Gene Expression | Immune activation marker |
| CX3CL1 (Fractalkine) | Gene Expression | Progression marker |

---

## 3. Idea Generation: Protein Structure Prediction (AlphaFold-Style)

### 3.1 Task Specification

**Question:** You are a top-tier researcher in your field. Based on the following context, please generate a novel and detailed research proposal.

### 3.2 Related Work Summary

| Reference | Contribution | Limitation |
|-----------|--------------|------------|
| Senior et al. (2020) | Deep learning for inter-residue distances | Multiple post-processing stages, no atomic accuracy for novel folds |
| Yang et al. (2020) | Inter-residue orientation prediction | Limited end-to-end learning, lower performance on complex proteins |
| AlQuraishi (2019) | End-to-end differentiable structure prediction | Lower accuracy than pipelines, struggles without templates |
| Marks et al. (2011) | Coevolutionary analysis of MSAs | Good contact prediction but no accurate atomic models |

### 3.3 Identified Challenges

1. **Atomic-level accuracy** without homologous structural templates
2. **Integration** of physical, geometric, and evolutionary information
3. **Shallow MSAs** with limited evolutionary signal
4. **Large proteins** and complex/novel topologies
5. **Confidence quantification** for downstream applications

### 3.4 Reference Solution: AlphaFold Architecture

**Core Idea:**
AlphaFold introduces an end-to-end deep learning architecture that jointly embeds MSAs and pairwise residue features, iteratively refines 3D atomic structures through Evoformer and Invariant Point Attention modules, integrates geometric and evolutionary constraints, leverages self-distillation from unlabeled data, and produces accurate, scalable predictions with robust per-residue confidence estimates.

### 3.5 Implementation Steps (Ground Truth)

```
Step 1: Collect and preprocess protein sequence/structure data
        - Sources: PDB, UniRef90, BFD, Uniclust30, MGnify
        
Step 2: Construct MSAs and retrieve structural templates
        - Tools: HHBlits, jackhmmer, HHSearch
        
Step 3: Initialize neural network
        - Encode MSA and pairwise features
        - Build Evoformer trunk with attention and triangle update blocks
        
Step 4: Process MSA and pair features
        - Stacked Evoformer blocks
        - Information exchange and representation enhancement
        
Step 5: Feed to structural module
        - Invariant point attention
        - Equivariant transformations
        - Iterative 3D coordinate refinement
        
Step 6: Apply training losses
        - FAPE loss (Frame-Aligned Point Error)
        - Distogram loss
        - BERT-style MSA masking loss
        - Auxiliary side-chain/violation losses
        
Step 7: Self-distillation augmentation
        - Generate high-confidence predictions on unlabeled sequences
        - Retrain with mixed supervised and distillation data
        
Step 8: Inference pipeline
        - Ensemble predictions
        - Model selection by confidence scores
        - Amber force field relaxation
        
Step 9: Evaluation
        - CASP14 targets
        - Recent PDB structures
        - Per-residue confidence (pLDDT) and TM-score estimates
```

### 3.6 Evaluation Metrics

| Metric | Definition | Usage |
|--------|------------|-------|
| **IDDT** | Local Distance Difference Test | Superposition-free metric for local atomic accuracy |
| **IDDT-Cα** | IDDT for backbone atoms | Backbone-specific accuracy |
| **GDT** | Global Distance Test | CASP standard for domain accuracy |
| **TM-score** | Template Modeling score | Global structural similarity |
| **Cα r.m.s.d.95** | RMSD over best-aligned 95% residues | Outlier-robust accuracy |
| **pLDDT** | Predicted LDDT | Per-residue confidence |
| **pTM** | Predicted TM-score | Global confidence |

### 3.7 Expected Outcomes

- Median backbone accuracy: **0.96 Å r.m.s.d.95** on CASP14
- All-atom accuracy: **1.5 Å** (95% CI: 1.2–1.6 Å)
- Outperforms next-best method by **>1.8 Å**
- pLDDT correlation with true accuracy: **Pearson r > 0.75**
- Scales to proteins **>2,000 residues**

---

## 4. Idea Generation: Drug Discovery (JT-VAE Molecular Generation)

### 4.1 Task Specification

Generate a research proposal for molecular generative models in drug discovery.

### 4.2 Related Work

| Method | Approach | Validity Rate |
|--------|----------|---------------|
| CVAE | SMILES generation | ~40% |
| Grammar VAE | Syntactic constraints | ~50% |
| SD-VAE | Semantic constraints | 43.5% |
| GraphVAE | Adjacency matrices | Variable |
| Atom-by-Atom LSTM | Sequential generation | 89.2% |

### 4.3 Reference Solution: Junction Tree VAE

**Core Idea:**
Represent molecules as junction trees of valid chemical substructures, enabling a two-stage variational autoencoder: first generating a tree-structured scaffold of subgraphs, then assembling these into a molecular graph using message passing.

### 4.4 Implementation Steps

```
Step 1: Tree decomposition
        - Construct junction tree of valid substructures
        - Build cluster vocabulary (~780 unique substructures)

Step 2: Encode molecular graph
        - Message passing neural network
        - Graph latent representation

Step 3: Encode junction tree
        - Tree message passing neural network
        - Tree latent representation

Step 4: Concatenate embeddings
        - Full latent representation

Step 5: Decode junction tree
        - Top-down sequential generation
        - Feasibility checks
        - Teacher forcing during training

Step 6: Assemble molecular graph
        - Sequential cluster merging
        - Neural scoring for candidate combinations

Step 7: Handle stereochemistry
        - Enumerate possible isomers
        - Neural scoring for selection

Step 8: Property-driven optimization
        - Joint training with property predictor
        - Gradient-based or Bayesian optimization in latent space

Step 9: Evaluate
        - Reconstruction accuracy
        - Validity rate
        - Property optimization improvement
```

### 4.5 Evaluation Metrics

| Metric | Definition | JT-VAE Result |
|--------|------------|---------------|
| **Reconstruction Accuracy** | % molecules correctly reconstructed | 76.7% |
| **Validity** | % chemically valid (RDKit) | **100%** |
| **Novelty** | Fraction not in training set | High |
| **Optimization Improvement** | Average property gain | Target scores up to 5.3 |
| **Tanimoto Similarity** | Morgan fingerprint similarity | Maintained |
| **Success Rate** | Valid + improved + constrained | >80% |

### 4.6 Data Sources

- **ZINC Database:** ~250,000 drug-like molecules
- **Cluster vocabulary:** 780 unique substructures (rings, bonds, atoms)
- **Split:** Standard Kusner et al. (2017) partitioning

---

## 5. Experimental Reasoning: Nanoparticle-Based Cancer Immunotherapy

### 5.1 Task Description

Multi-image reasoning task requiring integration of:
1. Molecular pathway diagram (Siglec-10/CD24 axis)
2. Nanoparticle delivery strategies
3. Drug delivery classification

### 5.2 Question

According to the images:
- If one wants to inhibit tumor development by targeting non-tumor cells, which cells should the monoclonal antibody be made against?
- Which delivery method can achieve inhibition from a deeper level?
- Which type does this method belong to?

### 5.3 Options

| Option | Target | Method | Type |
|--------|--------|--------|------|
| A | Siglec-10 | A | A |
| B | Siglec-10 | A | B |
| C | Siglec-10 | B | A |
| D | Siglec-10 | B | B |
| **E** | **Siglec-10** | **C** | **A** |
| F | CD24 | A | A |
| G | CD24 | A | B |
| H | CD24 | B | A |
| I | CD24 | B | B |
| J | CD24 | C | A |

### 5.4 Reasoning Steps (Ground Truth)

```
Step 1: Identify target proteins
        - Available targets: Siglec-10, CD24
        - Siglec-10 is on non-tumor cells (macrophages)
        - CD24 is on tumor cells

Step 2: Select target based on requirement
        - "Target non-tumor cells" → Siglec-10

Step 3: Analyze delivery strategies (Figure 2)
        - Strategy A: Direct antibody blocking on cell surface
        - Strategy B: Direct antibody blocking on cell surface
        - Strategy C: siRNA to inhibit protein expression at nucleic acid level

Step 4: Determine "deeper level" approach
        - Strategy C (siRNA) works at genetic/nucleic acid level
        - More fundamental inhibition than surface blocking

Step 5: Identify delivery type (Figure 3)
        - siRNA-delivering nanomaterials: no surface antibodies
        - Passive targeting mechanism
        - Type A: Passive targeting

Step 6: Conclusion
        - Answer: E (Siglec-10; C; A)
```

---

## 6. Life Science Performance Benchmarks

### 6.1 Model Performance on Life Science Tasks

| Model | Deep Research | Idea Gen | Wet Exp SS | Wet Exp PA | Exp Reasoning |
|-------|---------------|----------|------------|------------|---------------|
| GPT-5 | 9.20% | Moderate | ~30% | ~35% | 37.50% |
| Gemini-3-Pro | 12.00% | High | ~32% | ~37% | 41.92% |
| Claude-Sonnet-4.5 | 11.49% | High | ~30% | ~36% | 37.80% |
| Qwen3-Max | 16.28% | Moderate | ~33% | ~40% | ~38% |

### 6.2 Life Science-Specific Findings

**Deep Research:**
- Life science questions require integrating scattered evidence across multiple papers
- Biomarker discovery tasks show especially low exact match rates
- Numerical data extraction (concentrations, dosages) is particularly challenging

**Idea Generation:**
- Feasibility scores uniformly low (14-23) for wet lab proposals
- Missing: sample acquisition plans, ethical considerations, timeline estimates
- Strong novelty but poor implementability

**Wet Experiment:**
- Life science protocols have highest complexity (branching, temporal sampling)
- NSCLC immunotherapy case: models collapse longitudinal designs
- Multi-sample tracking failures common

**Experimental Reasoning:**
- Life science among hardest domains (after Materials Science)
- Comparative reasoning with biological images particularly challenging
- Pathology image interpretation requires domain-specific training

---

## 7. BioMate Application Guidelines

### 7.1 Protocol Template Development

Based on the wet experiment examples, BioMate should develop templates for:

| Protocol Type | Key Elements | Validation Points |
|---------------|--------------|-------------------|
| **IHC Staining** | Fixation → Embedding → Sectioning → Staining → Scoring | Antibody concentrations, incubation times |
| **FFPE Processing** | Tissue prep → DNA/RNA extraction → Storage | Extraction kit compatibility, storage conditions |
| **Flow Cytometry** | Blood collection → PBMC isolation → Panel staining → Analysis | Tube types, centrifugation parameters |
| **Gene Expression** | RNA isolation → Quality check → Platform selection → Analysis | RIN scores, panel selection |

### 7.2 Multi-Timepoint Workflow Support

Critical for immunotherapy monitoring:

```
Baseline (Day 0):
├── Tumor biopsy → IHC scoring
├── Blood sample → PBMC isolation → Baseline immune profiling
└── Blood sample → Plasma → Cytokine panel

Treatment (Day 1):
└── Drug administration

Post-Treatment (Day 7, 14, 21...):
├── Blood sample → PBMC → T-cell dynamics
├── Blood sample → Plasma → Cytokine monitoring
└── Optional: On-treatment biopsy → Response assessment
```

### 7.3 Quality Control Checkpoints

| Stage | QC Parameter | Acceptable Range |
|-------|--------------|------------------|
| Tissue fixation | Fixation time | 6-72 hours in 10% NBF |
| RNA extraction | RIN score | >7 for gene expression |
| Antibody staining | Positive/negative controls | Clear discrimination |
| Flow cytometry | Viability | >90% live cells |
| Gene expression | Housekeeping genes | Stable Ct values |

---

## 8. Appendix: Complete Discipline Distribution

### 8.1 Task Distribution by Discipline

| Discipline | Deep Research | Idea Gen | Dry Exp | Wet Exp | Exp Reasoning |
|------------|---------------|----------|---------|---------|---------------|
| Life Science | 87 | 45 | 35 | **28** | 48 |
| Chemistry | 42 | 38 | 28 | 15 | 35 |
| Physics | 55 | 42 | 45 | 8 | 42 |
| Materials | 38 | 35 | 32 | 17 | 38 |
| Earth Science | 48 | 30 | 25 | 0 | 35 |
| Astronomy | 35 | 28 | 28 | 0 | 28 |
| Neuroscience | 28 | 22 | 18 | 0 | 25 |
| Energy | 22 | 20 | 18 | 0 | 18 |
| Information | 28 | 35 | 25 | 0 | 22 |
| Math | 35 | 20 | 17 | 0 | 0 |

**Note:** Life Science has the most Wet Experiment samples (28), reflecting the complexity of biological protocols.

---

*Document prepared for BioMate AI strategic planning*
*Source: SGI-Bench (arXiv:2512.16969v1, December 2025)*
*Life Science coverage: 243 total samples across 7 research directions*
