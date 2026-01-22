# AI Tools Comparison: New vs Existing Tools

**Generated: 2026-01-21**
**Purpose: Document for later discussion on tool selection and integration strategy**

---

## Executive Summary

This document analyzes the overlap between the **14 new AI-powered bioinformatics tools** and the **existing indexed tools/workflows** in Biomate. The goal is to determine:
1. Which existing tools can be replaced by the new AI tools
2. Which new tools provide entirely new capabilities
3. Why Biomate should select these new tools over existing alternatives

---

## 1. Existing Tools Inventory

### Structure Prediction
| Existing Tool | Location | Function |
|---------------|----------|----------|
| AlphaFold CLI | `biomni_workflows/galaxy/tools/cli/alphafold/` | Basic structure prediction (outdated wrapper) |

### Protein Analysis
| Existing Tool | Location | Function |
|---------------|----------|----------|
| Compare Protein Structures | `systems_biology/compare_protein_structures.xml` | Structural alignment comparison |
| Analyze Protein Conservation | `biochemistry/analyze_protein_conservation.xml` | MSA + phylogenetic analysis |
| Predict Protein Disorder | `biophysics/predict_protein_disorder_regions.xml` | Disorder region prediction |

### Drug Discovery
| Existing Tool | Location | Function |
|---------------|----------|----------|
| AutoDock Vina | `pharmacology/docking_autodock_vina.xml` | Traditional molecular docking |
| Binding Affinity (1D) | `pharmacology/predict_binding_affinity_protein_1d_sequence.xml` | Sequence-based binding prediction |
| ADMET Prediction | `pharmacology/ADMET_pred.xml` | Basic ADMET properties |
| Physicochemical Props | `pharmacology/calculate_physicochemical_properties.xml` | RDKit-based calculations |

### Genomics/Single-Cell
| Existing Tool | Location | Function |
|---------------|----------|----------|
| Cell Type Annotation | `genomics/` | scRNA-seq annotation |
| Harmony Embeddings | `genomics/` | Batch correction |
| scVI Embeddings | `genomics/` | Variational inference embeddings |
| State Embeddings | `genomics/` | General state representations |
| Gene Expression Analysis | `genomics/` | DESeq2, limma, edgeR |

### CLI Tools (Traditional)
| Category | Tools |
|----------|-------|
| Alignment | BLAST, DIAMOND, Bowtie2, BWA, HISAT2, STAR |
| Sequencing | FastQC, Trimmomatic, Cutadapt, Salmon, Kallisto |
| Variants | BCFtools, GATK, SAMtools, SNPEff |
| Structure | **Foldseek** (structure search) |

---

## 2. New AI Tools Overview

### Structure Prediction (4 models + 3 APIs)
| Tool | Type | Size | Key Advantage |
|------|------|------|---------------|
| **Boltz-2** | Local/API | 103 GB | Protein-ligand + binding affinity |
| **Chai-1** | Local/API | 15 GB | Multi-modal (protein/DNA/RNA/ligand/glycans) |
| **AlphaFold 3** | Local/API | ~1 TB | 50% improvement over AF2 for complexes |
| **ESMFold** | API only | N/A | 60x faster than AF2 (single chains) |

### Drug Discovery (3 tools)
| Tool | Type | Size | Key Advantage |
|------|------|------|---------------|
| **DrugCLIP** | Local/API | ~5 GB | **10 million times faster** than docking |
| **SynCraft** | Local | ~1 GB | AI retrosynthesis (NEW capability) |
| **GenMol** | Local | ~5 GB | Generative molecular design (NEW capability) |

### Protein Analysis (2 tools)
| Tool | Type | Size | Key Advantage |
|------|------|------|---------------|
| **ProFam** | Local | 1.5 GB | Deep learning protein family classification |
| **ProTrek** | Local/API | ~3 GB | **100x faster** than Foldseek, text-based search |

### Single-Cell (1 tool)
| Tool | Type | Size | Key Advantage |
|------|------|------|---------------|
| **STATE** | Local | 28 GB | Perturbation response prediction (NEW capability) |

### Antibody Design (1 tool)
| Tool | Type | Size | Key Advantage |
|------|------|------|---------------|
| **scFv-pMPNN** | Local | ~23 GB | AI antibody design (NEW capability) |

### Genomics (3 tools)
| Tool | Type | Size | Key Advantage |
|------|------|------|---------------|
| **Evo 2** | Local/API | 100 GB | DNA foundation model, 1M bp context |
| **OmniGenome** | Local | ~15 GB | Multi-task regulatory element prediction |
| **MAMMAL** | Local | ~9 GB | Multi-species genomic analysis |

### Image Analysis (1 tool)
| Tool | Type | Size | Key Advantage |
|------|------|------|---------------|
| **Cambrian-1** | Local | ~23 GB | Vision-language for biological images |

---

## 3. Detailed Comparison by Function

### A. Structure Prediction

**EXISTING:**
- Old AlphaFold CLI wrapper (basic, outdated)

**NEW AI TOOLS:**
- Boltz-2, Chai-1, AlphaFold 3, ESMFold API

**RECOMMENDATION: REPLACE**

| Metric | Existing | New AI Tools |
|--------|----------|--------------|
| Accuracy | AF2 baseline | 50%+ better (AF3) |
| Speed | Hours | Minutes (ESMFold) |
| Multi-modal | Protein only | Protein/DNA/RNA/ligand |
| Binding affinity | No | Yes (Boltz-2) |
| Cost | Compute-heavy | FREE APIs available |

**Why new tools are better:**
1. AF3/Boltz-2/Chai-1 predict **complexes**, not just single proteins
2. ESMFold API is **60x faster** for single chains
3. FREE APIs available (no local compute needed)
4. Binding affinity prediction included (Boltz-2)

---

### B. Drug Discovery / Virtual Screening

**EXISTING:**
- AutoDock Vina (traditional docking)
- 1D sequence binding affinity
- Basic ADMET

**NEW AI TOOLS:**
- DrugCLIP, SynCraft, GenMol

**RECOMMENDATION: REPLACE + ADD NEW CAPABILITIES**

| Metric | AutoDock Vina | DrugCLIP |
|--------|---------------|----------|
| Speed | ~1 hr/compound | **10M compounds/hr** |
| Accuracy | Physics-based | AI-learned |
| Setup | Complex (prep required) | Simple (SMILES input) |
| Use case | Small libraries | **Billion-scale screening** |

**New capabilities (not replacements):**
- **SynCraft**: Retrosynthesis planning - tells you HOW to synthesize a drug
- **GenMol**: Generative design - creates NEW molecules with desired properties

---

### C. Protein Search

**EXISTING:**
- Foldseek (CLI tool for structure search)

**NEW AI TOOLS:**
- ProTrek (trimodal search)

**RECOMMENDATION: REPLACE**

| Metric | Foldseek | ProTrek |
|--------|----------|---------|
| Speed | Fast | **100x faster** |
| Search modes | Structure only | Structure + Sequence + **TEXT** |
| Database | Custom | **5B+ proteins pre-indexed** |
| Query type | PDB file | Text description, e.g., "kinase that binds ATP" |

**Why ProTrek is revolutionary:**
- Search by **natural language function description**
- Example: "Find proteins similar to insulin receptor that bind small molecules"
- No need to have a structure to search

---

### D. Protein Family Analysis

**EXISTING:**
- MSA-based conservation analysis
- Manual family assignment

**NEW AI TOOLS:**
- ProFam

**RECOMMENDATION: REPLACE FOR CLASSIFICATION**

| Metric | Conservation Analysis | ProFam |
|--------|----------------------|--------|
| Method | MSA + phylogenetics | Deep learning |
| Input | Multiple sequences | Single sequence |
| Output | Conservation scores | Family classification + fitness |
| Use case | Understanding evolution | **Predicting function** |

---

### E. Single-Cell Perturbation

**EXISTING:**
- General embedding methods (Harmony, scVI, TranscriptFormer)
- Cell type annotation

**NEW AI TOOLS:**
- STATE

**RECOMMENDATION: ADD (NEW CAPABILITY)**

| Metric | Existing Embeddings | STATE |
|--------|--------------------|----|
| Purpose | Batch correction, visualization | **Predict cellular response** |
| Input | scRNA-seq data | scRNA-seq + perturbation |
| Output | Embeddings | **Predicted gene expression after perturbation** |
| Use case | Analysis | **Virtual experiments** |

**STATE enables:**
- Predict cell response to gene knockdown
- Predict cell response to drug treatment
- Predict cell response to CRISPR editing
- **Virtual experiments before wet lab**

---

### F. Antibody Design

**EXISTING:**
- None

**NEW AI TOOLS:**
- scFv-pMPNN

**RECOMMENDATION: ADD (NEW CAPABILITY)**

This is an entirely new capability. No existing tools in Biomate can design antibody sequences.

---

### G. DNA/Genomics

**EXISTING:**
- Traditional alignment (BLAST, Bowtie2, etc.)
- Variant calling (GATK, BCFtools)
- Gene expression analysis

**NEW AI TOOLS:**
- Evo 2, OmniGenome, MAMMAL

**RECOMMENDATION: ADD (COMPLEMENT EXISTING)**

| Metric | Traditional Tools | New AI Tools |
|--------|-------------------|--------------|
| Approach | Reference-based | Foundation models |
| Context | Local | **1M bp** (Evo 2) |
| Tasks | Alignment, variants | Generation, effect prediction |
| Use case | Analysis | **Design + prediction** |

**New capabilities:**
- **Evo 2**: Generate DNA sequences, predict variant effects
- **OmniGenome**: Predict promoters, splice sites, enhancers, conservation
- **MAMMAL**: Cross-species genomic analysis

---

## 4. Summary: Replace vs Add

| Function | Recommendation | Existing Tool | New Tool | Improvement |
|----------|----------------|---------------|----------|-------------|
| Structure Prediction | **REPLACE** | AlphaFold CLI | AF3, Boltz-2, Chai-1, ESMFold | 50% accuracy, 60x speed |
| Drug Screening | **REPLACE** | AutoDock Vina | DrugCLIP | **10M x faster** |
| Protein Search | **REPLACE** | Foldseek | ProTrek | **100x faster**, text search |
| Protein Family | **REPLACE** | Conservation | ProFam | DL-based, single sequence |
| Retrosynthesis | **ADD NEW** | None | SynCraft | New capability |
| Generative Design | **ADD NEW** | None | GenMol | New capability |
| Perturbation Pred. | **ADD NEW** | None | STATE | New capability |
| Antibody Design | **ADD NEW** | None | scFv-pMPNN | New capability |
| DNA Foundation | **ADD NEW** | Traditional | Evo 2, OmniGenome | New capability |
| Bio Image VQA | **ADD NEW** | None | Cambrian-1 | New capability |

---

## 5. Why Biomate Should Select These Tools

### Speed Improvements
| Tool | Improvement |
|------|-------------|
| DrugCLIP | 10,000,000x faster than traditional docking |
| ProTrek | 100x faster than Foldseek |
| ESMFold | 60x faster than AlphaFold 2 |

### Accuracy Improvements
| Tool | Improvement |
|------|-------------|
| AlphaFold 3 | 50%+ improvement over AF2 for complexes |
| Boltz-2 | State-of-art binding affinity |

### New Capabilities (Not Possible Before)
1. **Search proteins by text description** (ProTrek)
2. **Design antibody sequences** (scFv-pMPNN)
3. **Plan drug synthesis routes** (SynCraft)
4. **Generate molecules with properties** (GenMol)
5. **Predict cell responses to perturbations** (STATE)
6. **Generate DNA sequences** (Evo 2)
7. **Understand biological images with language** (Cambrian-1)

### Cost Considerations
- **FREE APIs** available for ESMFold, AlphaFold DB, AlphaFold 3 Server, DrugCLIP, ProTrek
- No need for expensive GPU infrastructure for many use cases

---

## 6. Docker Images on AWS ECR

All 8 Docker images pushed to AWS ECR for testing:

```
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/drugclip
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz
399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1
```

---

## 7. Discussion Points

### Questions for Team Discussion:

1. **Deprecation Strategy**: Should we deprecate existing tools (AutoDock Vina, Foldseek, old AlphaFold CLI) or keep them as alternatives?

2. **API vs Local**: Given FREE APIs are available, should we prioritize API wrappers or local execution?

3. **GPU Resource Allocation**: Large models (Boltz-2 ~103GB, Evo 2 ~100GB) exceed GB10 capacity. Should we:
   - Use cloud GPU instances?
   - Use API alternatives?
   - Hold for future hardware?

4. **Integration Priority**: Which tools should be integrated first?
   - Recommended: FREE API tools (ESMFold, AlphaFold, DrugCLIP Search, ProTrek Search)
   - Then: Small local models (ProFam, STATE, scFv-pMPNN, SynCraft)
   - Finally: Large models (Boltz-2, Chai-1, Evo 2)

5. **Workflow Updates**: Which existing workflows need to be updated to use new tools?

---

## Appendix: File Locations

### New AI Tools
- Docker files: `/home/yzhang/biomate/backend/docker/biomate-ai-tools/`
- Wrappers: `/home/yzhang/biomate/backend/tools/biomate_ai_tools/scripts/`
- XML definitions: `/home/yzhang/biomate/backend/tools/biomate_ai_tools/`
- Models: `/home/yzhang/biomate/models/`
- Venv: `/home/yzhang/biomate/backend/tools/biomate_ai_tools/.venv/`

### Existing Tools
- Galaxy tools: `/home/yzhang/biomate/backend/biomni_workflows/galaxy/tools/`
- CLI tools: `/home/yzhang/biomate/backend/biomni_workflows/galaxy/tools/cli/`
- Workflows: `/home/yzhang/biomate/backend/biomni_workflows/galaxy/subworkflows/`