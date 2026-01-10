# Comprehensive Workflow Platform Comparison: Galaxy IWC vs nf-core vs Biomni

**Date:** 2025-12-04
**Purpose:** Complete technical comparison with benchmark evidence

---

## Executive Summary

| Aspect | Galaxy IWC | nf-core | Biomni |
|--------|------------|---------|--------|
| **Primary Focus** | GUI-based workflows | Production pipelines | AI-driven analysis |
| **Total Workflows** | ~115 | 141 pipelines | 122 workflows |
| **Subworkflows/Modules** | Bundled | 1,400+ modules | 275 subworkflows |
| **Tool Functions** | 334 | 1,651 | 241 (+ 128 internal) |
| **Execution Model** | Galaxy server | Nextflow + Docker | Python API / Galaxy |
| **User Interface** | Web GUI | CLI | AI chat / API |
| **Best For** | Non-programmers, research flexibility | Production, reproducibility | Exploratory analysis, AI assistance |

---

## Part 1: Galaxy IWC vs nf-core (Tool Quality Comparison)

### 1.1 RNA-seq Quantification

| Aspect | Galaxy IWC | nf-core | Winner | Evidence |
|--------|------------|---------|--------|----------|
| **Multi-mapping handling** | featureCounts (discards) | salmon/kallisto (EM) | **nf-core** | 5-40% reads are multi-mapped (Deschamps-Francoeur 2020) |
| **Gene detection** | Misses overlapping genes | Correct attribution | **nf-core** | featureCounts missed 182 DE genes in brain study (Zytnicki 2017) |
| **Algorithm** | Simple counting | Expectation-maximization | **nf-core** | EM "more accurate than rescue method" |

**Citation:** Deschamps-Francoeur et al. (2020). *Computational and Structural Biotechnology Journal*. https://pmc.ncbi.nlm.nih.gov/articles/PMC7330433/

### 1.2 Viral Variant Calling

| Aspect | Galaxy IWC (LoFreq) | nf-core (bcftools) | Winner | Evidence |
|--------|---------------------|-------------------|--------|----------|
| **Pure samples** | 94% sens, 100% PPV | Good | **Galaxy** | Wilm 2012: 0.05% VAF detection |
| **Mixed/wastewater** | "Least reliable" | High precision | **nf-core** | Bassano 2023: LoFreq highest FP |
| **Amplicon support** | No primer handling | iVar integrated | **nf-core** | Essential for ARTIC protocols |

**Citation:** Bassano et al. (2023). *Microbial Genomics*. https://www.microbiologyresearch.org/content/journal/mgen/10.1099/mgen.0.000933

### 1.3 ChIP-seq / ATAC-seq / CUT&RUN

| Aspect | Galaxy IWC | nf-core | Winner | Evidence |
|--------|------------|---------|--------|----------|
| **ChIP-seq QC** | Basic MultiQC | phantompeakqualtools (NSC/RSC) | **nf-core** | ENCODE requires NSC>1.05, RSC>0.8 |
| **ATAC-seq QC** | Generic | ATACseqQC (TSS enrichment) | **nf-core** | TSS enrichment essential for QC |
| **CUT&RUN peaks** | MACS2 | SEACR | **nf-core** | MACS2 over-calls 1000x+ (Cheng 2024) |

**Citation:** Cheng et al. (2024). *Frontiers in Genetics*. https://pmc.ncbi.nlm.nih.gov/articles/PMC11464419/

### 1.4 Single-Cell RNA-seq

| Aspect | Galaxy IWC | nf-core | Winner | Evidence |
|--------|------------|---------|--------|----------|
| **Default aligner** | STARsolo | STARsolo/kallisto | **Tie** | Both offer STARsolo |
| **kallisto option** | Not offered | Available | **Galaxy (safer)** | kallisto misses 1/9 cell types (Tian 2020) |
| **Speed** | 35 min | 35 min (STARsolo) | **Tie** | 10x faster than CellRanger |

**Citation:** Tian et al. (2020). *G3: Genes|Genomes|Genetics*. https://academic.oup.com/g3journal/article/10/5/1775/6026272

### 1.5 Overall Quality Verdict: Galaxy vs nf-core

| Category | Galaxy IWC | nf-core | Notes |
|----------|------------|---------|-------|
| RNA-seq quantification | ⚠️ Suboptimal | ✅ Better | EM vs counting |
| Variant calling (pure) | ✅ Better | ⚠️ Good | LoFreq ultra-sensitive |
| Variant calling (mixed) | ❌ Poor | ✅ Better | LoFreq fails on mixed |
| ChIP-seq QC | ❌ Missing metrics | ✅ Complete | ENCODE compliance |
| ATAC-seq QC | ❌ Missing metrics | ✅ Complete | TSS enrichment |
| CUT&RUN/CUT&Tag | ❌ Wrong tool | ✅ Correct | SEACR vs MACS2 |
| scRNA-seq | ✅ Safe default | ⚠️ Risky options | kallisto problems |
| **Overall** | **Research use** | **Production use** | nf-core more rigorous |

---

## Part 2: Biomni Architecture and Capabilities

### 2.1 Biomni Tool Inventory

| Category | Tool Functions | Parent Libraries | Type |
|----------|----------------|------------------|------|
| **Python functions** | 109 | 10 major libraries | API calls |
| **R functions** | 58 | 8 packages | R bridge |
| **CLI wrappers** | 74 | 17 tools | subprocess |
| **Total** | **241** | 46 | - |

### 2.2 Biomni Workflows and Subworkflows

| Metric | Count |
|--------|-------|
| Main workflows | 122 |
| Subworkflows | 275 |
| Domains covered | 17 |

**Domain Distribution:**

| Domain | Workflows | Subworkflows | Key Functions |
|--------|-----------|--------------|---------------|
| genomics | 14 | 25 | scRNA-seq, ChIP-seq, GSEA, gene conversion |
| bioimaging | 8 | 12 | segmentation, registration, visualization |
| biochemistry | 8 | 12 | enzyme kinetics, CD spectra, ITC |
| cell_biology | 6 | 10 | cell cycle, motility, FACS |
| cancer_biology | 6 | 8 | DDR network, CNV, NMF |
| immunology | 6 | 10 | ATAC-seq, flow cytometry, cytokines |
| molecular_biology | 6 | 10 | ORF annotation, plasmid, primers |
| pharmacology | 6 | 8 | docking, ADMET, drug repurposing |
| genetics | 5 | 8 | liftover, fine-mapping, CRISPR |
| microbiology | 5 | 8 | genome annotation, growth modeling |
| others | 52 | 164 | Various specialized analyses |

### 2.3 Biomni Key Libraries

| Library | Functions | Capabilities |
|---------|-----------|--------------|
| **Scanpy** | 21 | Full scRNA-seq: QC, normalization, clustering, DE |
| **Biopython** | 18 | Sequence I/O, BLAST, phylogenetics |
| **OpenCV/skimage** | 35 | Image segmentation, morphology, analysis |
| **RDKit** | 12 | Molecule handling, fingerprints, properties |
| **gget** | 5 | Gene info, sequences, enrichment |
| **COBRApy** | 6 | Metabolic modeling, FBA |
| **DESeq2/edgeR** | 20 | Differential expression (R) |
| **Seurat** | 10 | scRNA-seq analysis (R) |

### 2.4 Biomni CLI Tool Coverage

| Tool | Commands | Overlap with Galaxy/nf-core |
|------|----------|----------------------------|
| bwa | mem, index, aln | ✅ All three |
| samtools | view, sort, index, stats | ✅ All three |
| bcftools | call, filter, view | ✅ All three |
| bedtools | intersect, coverage | ✅ All three |
| MACS2 | callpeak | ✅ All three |
| STAR | alignReads | ✅ All three |
| salmon | quant | ✅ All three |
| kallisto | quant | ✅ All three |
| BLAST | blastn, blastp | ✅ All three |
| foldseek | search | ❌ Biomni only |
| mmseqs | cluster | ❌ Biomni only |

---

## Part 3: Three-Way Platform Comparison

### 3.1 Execution Model

| Aspect | Galaxy IWC | nf-core | Biomni |
|--------|------------|---------|--------|
| **Execution** | Galaxy server | Nextflow engine | Python runtime |
| **Containerization** | Optional Docker | Required Docker/Singularity | Bundled Docker |
| **Scalability** | Galaxy cluster | SLURM/AWS/GCP native | Local/API |
| **Workflow Format** | `.ga` (JSON) | `.nf` (Nextflow DSL) | Python functions |
| **State Management** | Galaxy database | Nextflow work dir | In-memory / files |

### 3.2 User Interface

| Aspect | Galaxy IWC | nf-core | Biomni |
|--------|------------|---------|--------|
| **Primary Interface** | Web GUI | Command line | AI chat / Python API |
| **Learning Curve** | Low | Medium-High | Low (with AI) |
| **Customization** | GUI drag-drop | Edit config/DSL | Python code / prompts |
| **Parameter Tuning** | GUI forms | Config files | Function arguments |
| **Visualization** | Built-in | External tools | Integrated plots |

### 3.3 Domain Coverage

| Domain | Galaxy IWC | nf-core | Biomni |
|--------|------------|---------|--------|
| RNA-seq | ✅ | ✅ | ✅ |
| scRNA-seq | ✅ | ✅ | ✅ (stronger) |
| Variant calling | ✅ | ✅ | ✅ |
| ChIP-seq/ATAC-seq | ✅ | ✅ (stronger) | ✅ |
| Metagenomics | ✅ | ✅ (stronger) | ✅ |
| Proteomics | ✅ | ✅ | ⚠️ Limited |
| **Imaging** | ❌ | ⚠️ Limited | ✅ (strong) |
| **Drug discovery** | ❌ | ❌ | ✅ (strong) |
| **Lab automation** | ❌ | ❌ | ✅ (unique) |
| **Literature search** | ❌ | ❌ | ✅ (unique) |
| **Database queries** | ❌ | ❌ | ✅ (strong) |
| Structural biology | ⚠️ | ⚠️ | ✅ |

### 3.4 Workflow Complexity Handling

| Complexity | Galaxy IWC | nf-core | Biomni |
|------------|------------|---------|--------|
| **Linear pipelines** | ✅ | ✅ | ✅ |
| **Branching** | ✅ | ✅ | ✅ |
| **Conditional execution** | ⚠️ Limited | ✅ | ✅ (AI decides) |
| **Dynamic inputs** | ⚠️ Limited | ✅ | ✅ |
| **Parameter sweeps** | ❌ | ✅ | ✅ |
| **Ad-hoc exploration** | ⚠️ | ❌ | ✅ (strongest) |

### 3.5 Reproducibility

| Aspect | Galaxy IWC | nf-core | Biomni |
|--------|------------|---------|--------|
| **Container pinning** | Optional | Required | Bundled |
| **Version tracking** | Tool versions | Full env hash | Package versions |
| **Workflow sharing** | `.ga` export | Git + configs | Python scripts |
| **Provenance** | Galaxy history | Nextflow trace | Execution logs |

---

## Part 4: Detailed Comparison for Specific Domains

### 4.1 Single-Cell RNA-seq Comparison

| Step | Galaxy IWC | nf-core | Biomni |
|------|------------|---------|--------|
| **Alignment** | STARsolo | STARsolo/kallisto/alevin-fry | STARsolo (via CLI) |
| **Cell filtering** | DropletUtils | DropletUtils/CellBender | Scanpy (scrublet) |
| **Normalization** | Scanpy wrapper | External | `scanpy.pp.normalize_total` |
| **Clustering** | Scanpy wrapper | External | `scanpy.tl.leiden` |
| **DE analysis** | Scanpy wrapper | External | `scanpy.tl.rank_genes_groups` |
| **Cell type annotation** | Manual | External | `popV` (9 methods), `CellTypist`, `panhumanpy` |
| **Batch correction** | Scanpy wrapper | External | `scVI`, `Harmony`, `Scanorama` |
| **Visualization** | Built-in | External | Integrated matplotlib |
| **Completeness** | Full workflow | Preprocessing only | **Full workflow + AI guidance** |

**Biomni Unique Features:**
- `unsupervised_celltype_transfer_between_scRNA_datasets()` - Uses popV with 9 classifiers
- `create_scvi_embeddings_scRNA()` - Deep learning embeddings
- `get_uce_embeddings_scRNA()` - Universal cell embeddings
- `map_to_ima_interpret_scRNA()` - Interpretable cell mapping

### 4.2 ChIP-seq Comparison

| Step | Galaxy IWC | nf-core | Biomni |
|------|------------|---------|--------|
| **Alignment** | bowtie2 | BWA/bowtie2/chromap | bwa/bowtie2 |
| **Peak calling** | MACS2 | MACS2 | `perform_chipseq_peak_calling_with_macs2()` |
| **Motif analysis** | ❌ | HOMER | `find_enriched_motifs_with_homer()` |
| **QC metrics** | Basic | NSC/RSC/FRiP | Basic |
| **Chromatin interactions** | ❌ | ❌ | `analyze_chromatin_interactions()` |

### 4.3 Drug Discovery (Biomni Unique)

| Function | Description | External Tools |
|----------|-------------|----------------|
| `run_diffdock_with_smiles()` | AI-powered molecular docking | DiffDock |
| `docking_autodock_vina()` | Traditional docking | AutoDock Vina |
| `predict_admet_properties()` | ADMET prediction | DeepPurpose |
| `predict_binding_affinity_protein_1d_sequence()` | Binding affinity | DeepPurpose |
| `retrieve_topk_repurposing_drugs_from_disease_txgnn()` | Drug repurposing | TxGNN |
| `calculate_physicochemical_properties()` | Molecular properties | RDKit |

**Neither Galaxy nor nf-core have equivalent drug discovery capabilities.**

### 4.4 Bioimaging (Biomni Strong)

| Function | Description | Methods |
|----------|-------------|---------|
| `segment_with_nn_unet()` | Deep learning segmentation | nnU-Net |
| `segment_and_analyze_microbial_cells()` | Cell segmentation | Cellpose |
| `quick_deformable_registration()` | Image registration | ANTs |
| `analyze_protein_colocalization()` | Colocalization analysis | OpenCV |
| `analyze_immunohistochemistry_image()` | IHC analysis | Custom |

**Galaxy has limited imaging; nf-core has molkart/spatialvi but less comprehensive.**

---

## Part 5: When to Use Each Platform

### 5.1 Use Galaxy IWC When:

| Scenario | Reason |
|----------|--------|
| Non-programmers need analysis | GUI-based, no coding |
| Research flexibility needed | Easy to modify steps |
| Ultra-sensitive variant detection | LoFreq detects 0.05% VAF |
| Training/education | Visual workflow building |
| Ad-hoc one-off analyses | Quick setup |

### 5.2 Use nf-core When:

| Scenario | Reason |
|----------|--------|
| Production pipelines | Reproducible, containerized |
| ENCODE compliance needed | NSC/RSC/FRiP metrics |
| Cloud execution (AWS/GCP) | Native cloud support |
| Large-scale processing | Scalable parallelization |
| Regulatory compliance | Full provenance tracking |
| CUT&RUN/CUT&Tag data | SEACR peak calling |
| Mixed/wastewater samples | Better variant calling precision |

### 5.3 Use Biomni When:

| Scenario | Reason |
|----------|--------|
| Exploratory analysis | AI guides exploration |
| Multi-domain analysis | 17 domains integrated |
| Drug discovery | Unique docking/ADMET tools |
| Bioimaging analysis | Strong segmentation/registration |
| Literature integration | Built-in PubMed/arXiv search |
| Database queries | UniProt, PDB, KEGG, etc. |
| Lab automation | PyLabRobot integration |
| Custom Python workflows | Direct API access |
| Non-expert users | AI explains results |
| scRNA-seq cell typing | 9 automated classifiers |

---

## Part 6: Integration Strategy

### 6.1 Complementary Usage

```
┌─────────────────────────────────────────────────────────────────┐
│                     BioMate Integration                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                  │
│  │  Galaxy  │    │ nf-core  │    │  Biomni  │                  │
│  │   IWC    │    │          │    │          │                  │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘                  │
│       │               │               │                         │
│       ▼               ▼               ▼                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │            Unified Docker Container                      │   │
│  │         biomate/biotools:arm64 (8GB)                    │   │
│  │                                                          │   │
│  │  • All CLI tools (STAR, salmon, samtools, etc.)         │   │
│  │  • Python packages (scanpy, gget, rdkit, etc.)          │   │
│  │  • R packages (DESeq2, Seurat, etc.)                    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Workflow Selection by Use Case:                                │
│  • Production RNA-seq → nf-core/rnaseq                         │
│  • Exploratory scRNA-seq → Biomni AI                           │
│  • GUI-based analysis → Galaxy IWC                             │
│  • Drug discovery → Biomni (unique)                            │
│  • CUT&RUN → nf-core/cutandrun                                 │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Recommended Combinations

| Analysis Type | Primary | Secondary | Reason |
|---------------|---------|-----------|--------|
| Production RNA-seq | nf-core | - | Best quantification |
| Exploratory scRNA-seq | Biomni | Galaxy | AI + visualization |
| Drug repurposing | Biomni | - | Unique capability |
| Variant surveillance | nf-core | - | Best for mixed samples |
| Research variant calling | Galaxy | - | LoFreq ultra-sensitive |
| ENCODE-compliant ChIP | nf-core | - | Required QC metrics |
| Imaging + genomics | Biomni | nf-core | Best imaging + production NGS |

---

## Part 7: Summary Statistics

### 7.1 Platform Comparison Matrix

| Metric | Galaxy IWC | nf-core | Biomni |
|--------|------------|---------|--------|
| Main workflows | ~115 | 141 | 122 |
| Modules/subworkflows | Bundled | 1,400+ | 275 |
| Tool functions | 334 | 1,651 | 241 |
| Domains | ~12 | ~15 | 17 |
| Execution | Server | Engine | Runtime |
| Interface | GUI | CLI | AI/API |
| Learning curve | Low | High | Low |
| Reproducibility | Medium | High | Medium |
| Flexibility | Medium | Low | High |
| AI assistance | ❌ | ❌ | ✅ |

### 7.2 Quality Ratings by Domain

| Domain | Galaxy IWC | nf-core | Biomni |
|--------|------------|---------|--------|
| RNA-seq | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| scRNA-seq | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Variant calling | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| ChIP-seq/ATAC | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Metagenomics | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Imaging | ⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| Drug discovery | ❌ | ❌ | ⭐⭐⭐⭐⭐ |
| Lab automation | ❌ | ❌ | ⭐⭐⭐⭐ |

---

## Conclusions

### Overall Rankings

1. **For Production Pipelines:** nf-core > Galaxy > Biomni
   - nf-core has superior containerization, reproducibility, and follows latest benchmarks

2. **For Research Flexibility:** Biomni > Galaxy > nf-core
   - Biomni's AI assistance and Python API enable rapid exploration

3. **For Tool Quality (NGS):** nf-core > Biomni > Galaxy
   - nf-core uses EM-based quantification, proper QC metrics, appropriate peak callers

4. **For Domain Breadth:** Biomni > nf-core > Galaxy
   - Biomni uniquely covers imaging, drug discovery, lab automation, literature

5. **For Accessibility:** Galaxy ≈ Biomni > nf-core
   - Galaxy has GUI; Biomni has AI assistance; nf-core requires CLI expertise

### Final Recommendation

**Use all three platforms strategically:**

- **nf-core** for production NGS workflows requiring reproducibility and ENCODE compliance
- **Galaxy IWC** for GUI-based analysis and research requiring workflow modification
- **Biomni** for AI-assisted exploration, drug discovery, imaging, and multi-domain integration

---

## References

1. Deschamps-Francoeur G, et al. (2020). *Comp Struct Biotechnol J*. https://pmc.ncbi.nlm.nih.gov/articles/PMC7330433/
2. Zytnicki M. (2017). *BMC Bioinformatics*. https://pmc.ncbi.nlm.nih.gov/articles/PMC5603007/
3. Bassano I, et al. (2023). *Microbial Genomics*. https://www.microbiologyresearch.org/content/journal/mgen/10.1099/mgen.0.000933
4. Wilm A, et al. (2012). *Nucleic Acids Research*. https://pmc.ncbi.nlm.nih.gov/articles/PMC3526318/
5. Cheng Y, et al. (2024). *Frontiers in Genetics*. https://pmc.ncbi.nlm.nih.gov/articles/PMC11464419/
6. Tian L, et al. (2020). *G3*. https://academic.oup.com/g3journal/article/10/5/1775/6026272
7. Schulze Brüning T, et al. (2022). *GigaScience*. https://pmc.ncbi.nlm.nih.gov/articles/PMC8848315/
8. Baruzzo G, et al. (2016). *Nature Methods*. https://pmc.ncbi.nlm.nih.gov/articles/PMC5792058/
