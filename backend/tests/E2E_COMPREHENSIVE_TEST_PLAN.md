# BioMate Comprehensive E2E Test Plan

**Date**: 2025-12-19
**Version**: 1.0
**Author**: Auto-generated for QA

---

## Executive Summary

This document defines comprehensive E2E testing covering:
1. **User Experience (UX) Tests** - Natural interaction flow, response quality
2. **Function Tests** - Feature correctness, API responses, data integrity
3. **Efficiency Tests** - Response times, resource usage, scalability

---

## Part 1: Top Priority Workflows

Based on platform comparison and usage patterns, these are the most important workflows:

### Tier 1: Core Bioinformatics (Highest Priority)

| # | Workflow | Domain | User Need | Expected Tools |
|---|----------|--------|-----------|----------------|
| 1 | RNA-seq Differential Expression | Genomics | Compare gene expression between conditions | FastQC, STAR/salmon, DESeq2 |
| 2 | Single-Cell RNA-seq Analysis | Genomics | Cluster cells, identify cell types | STARsolo, Scanpy, CellTypist |
| 3 | Variant Calling Pipeline | Genetics | Identify SNPs/indels from sequencing | BWA, GATK/bcftools |
| 4 | ChIP-seq Peak Calling | Epigenomics | Find protein binding sites | BWA, MACS2, deepTools |
| 5 | Protein Structure Prediction | Structural Bio | Predict 3D protein structure | AlphaFold, ESMFold |

### Tier 2: Specialized Analysis (High Priority)

| # | Workflow | Domain | User Need | Expected Tools |
|---|----------|--------|-----------|----------------|
| 6 | Drug-Target Interaction | Pharmacology | Predict drug binding | AutoDock Vina, DiffDock |
| 7 | Gene Set Enrichment | Genomics | Find enriched pathways | gProfiler, GSEA |
| 8 | Metagenomics Classification | Microbiology | Identify species in sample | Kraken2, MetaPhlAn |
| 9 | CRISPR sgRNA Design | Molecular Bio | Design gene knockout guides | CRISPRscan, Cas-OFFinder |
| 10 | Microscopy Segmentation | Bioimaging | Segment cells in images | Cellpose, StarDist |

### Tier 3: Data Integration (Medium Priority)

| # | Workflow | Domain | User Need | Expected Tools |
|---|----------|--------|-----------|----------------|
| 11 | Multi-omics Integration | Systems Bio | Combine RNA/protein/metabolite | MOFA, mixOmics |
| 12 | Phylogenetic Analysis | Evolution | Build evolutionary trees | MAFFT, RAxML, IQ-TREE |
| 13 | Metabolomics Annotation | Metabolomics | Identify metabolites | MS2ID, MetaboAnalyst |
| 14 | Flow Cytometry Analysis | Immunology | Analyze cell populations | FlowJo-like, Cytoflow |
| 15 | Clinical Trial Search | Literature | Find relevant trials | ClinicalTrials.gov API |

---

## Part 2: User Story Scenarios

### Story 1: RNA-seq Analysis for Publication
**Persona**: Dr. Sarah Chen, Postdoc preparing a Nature paper
**Goal**: Analyze RNA-seq data and get publication-ready methods section

```
User Journey:
1. Upload: "I have 6 RNA-seq samples (3 control, 3 treated)"
2. Request: "Analyze differential expression and give me the top genes"
3. Follow-up: "Generate a methods section with proper citations"
4. Export: "Export all citations as BibTeX for my paper"
```

**Expected Behaviors**:
- BioMate suggests appropriate pipeline (FastQC → STAR → DESeq2)
- Pilot run offered for large datasets (>50 samples)
- Citations displayed for each tool used
- Methods section generated in APA/numbered style
- BibTeX export available

### Story 2: Large-Scale scRNA-seq with Optimization
**Persona**: Dr. Michael Torres, Core facility manager
**Goal**: Process 200 single-cell samples with parameter optimization

```
User Journey:
1. Request: "I have 200 10X Genomics scRNA-seq samples to analyze"
2. Accept: Pilot run suggestion (10% = 20 samples)
3. Review: Pilot results and resource estimates
4. Optimize: Accept recommended parameters
5. Execute: Full run with optimized settings
```

**Expected Behaviors**:
- System suggests pilot run for >50 samples
- Pilot completes with timing/memory metrics
- Full run estimate provided (time, cost, memory)
- Parameter recommendations based on pilot
- Progress tracking during execution

### Story 3: Drug Discovery Workflow
**Persona**: Dr. Emily Watson, Medicinal chemist
**Goal**: Screen compounds against target protein

```
User Journey:
1. Input: "I want to dock these 10 compounds against EGFR protein"
2. Provide: SMILES strings and PDB ID
3. Execute: Docking workflow
4. Analyze: Binding poses and scores
5. Export: Results for further analysis
```

**Expected Behaviors**:
- Recognizes docking request, suggests AutoDock Vina or DiffDock
- Retrieves protein structure from PDB automatically
- Runs docking with appropriate parameters
- Provides visualization of binding poses
- Exports scores in standard format

### Story 4: Quick Database Query
**Persona**: Dr. James Liu, Graduate student
**Goal**: Quick lookup of gene/protein information

```
User Journey:
1. Ask: "What is the function of TP53?"
2. Follow-up: "Show me its protein structure"
3. Follow-up: "What drugs target it?"
```

**Expected Behaviors**:
- Quick response (<5 seconds) for database queries
- Information from UniProt, Gene Ontology
- AlphaFold structure link/visualization
- DrugBank/ChEMBL compound list
- No workflow generation for simple queries

### Story 5: Troubleshooting Failed Analysis
**Persona**: Dr. Anna Schmidt, New user
**Goal**: Understand why analysis failed and fix it

```
User Journey:
1. Upload: Invalid FASTQ file
2. Error: Clear error message explaining issue
3. Guide: Suggestions for fixing the problem
4. Retry: Successful after correction
```

**Expected Behaviors**:
- Clear, non-technical error messages
- Specific guidance on how to fix
- Input validation before execution
- Graceful error handling

---

## Part 3: Test Categories

### 3.1 User Experience (UX) Tests

| Test ID | Category | Description | Success Criteria |
|---------|----------|-------------|------------------|
| UX-01 | Response Quality | Natural language understanding | Correct intent detection >95% |
| UX-02 | Conversation Flow | Multi-turn dialogue coherence | Context maintained across turns |
| UX-03 | Error Messages | User-friendly error handling | Non-technical, actionable messages |
| UX-04 | Loading States | Progress indication | Visual feedback within 1s |
| UX-05 | Result Presentation | Clear output formatting | Structured, scannable results |
| UX-06 | Citation Display | Easy access to citations | One-click copy, visible badges |
| UX-07 | Pilot Run UX | Intuitive pilot configuration | <3 clicks to start pilot |
| UX-08 | Help & Guidance | Contextual assistance | Relevant suggestions offered |

### 3.2 Function Tests

| Test ID | Category | Description | Success Criteria |
|---------|----------|-------------|------------------|
| FN-01 | Workflow Generation | Correct tool selection | Appropriate tools for task |
| FN-02 | Parameter Defaults | Sensible default values | Best-practice parameters |
| FN-03 | Citation Accuracy | Correct DOI/PMID | Valid, formatted citations |
| FN-04 | Methods Generation | Publication-ready text | Grammatically correct, complete |
| FN-05 | Pilot Run Execution | Subset processing | Correct sample selection |
| FN-06 | Resource Estimation | Accurate predictions | Within 20% of actual |
| FN-07 | API Response Format | Schema compliance | All required fields present |
| FN-08 | Database Queries | Correct data retrieval | Accurate, current data |
| FN-09 | File Handling | Input/output processing | Correct formats, no corruption |
| FN-10 | Workflow Execution | End-to-end completion | Successful outputs |

### 3.3 Efficiency Tests

| Test ID | Category | Description | Success Criteria |
|---------|----------|-------------|------------------|
| EF-01 | Response Latency | Time to first response | <3s for simple queries |
| EF-02 | Workflow Gen Time | Time to generate workflow | <10s for standard workflows |
| EF-03 | Citation Export | BibTeX generation time | <2s for 20 citations |
| EF-04 | Pilot Overhead | Pilot vs full run time | <20% overhead ratio |
| EF-05 | Memory Usage | Peak memory consumption | Within resource limits |
| EF-06 | Concurrent Users | Multi-user performance | Stable with 10 concurrent |
| EF-07 | Large Dataset | Scalability | Linear scaling to 1000 samples |
| EF-08 | API Throughput | Requests per second | >10 req/s sustained |

---

## Part 4: Test Implementation Plan

### Phase 1: API-Level LLM Agent Tests (Immediate)

**File**: `e2e_comprehensive_llm_test.py`

```python
PRIORITY_SCENARIOS = [
    # Tier 1 - Core Bioinformatics
    {"name": "RNA-seq DE Analysis", "category": "genomics", ...},
    {"name": "scRNA-seq Cell Typing", "category": "genomics", ...},
    {"name": "Variant Calling", "category": "genetics", ...},

    # Citation & Pilot Features
    {"name": "Citation Export Flow", "category": "citation", ...},
    {"name": "Pilot Run Optimization", "category": "pilot", ...},

    # UX Scenarios
    {"name": "Error Recovery", "category": "ux", ...},
    {"name": "Quick Query", "category": "ux", ...},
]
```

### Phase 2: Browser-Based UI Tests (When Playwright Available)

**File**: `e2e_comprehensive_browser_test.py`

- Full UI interaction simulation
- Screenshot capture at each step
- Visual regression testing
- Accessibility checks

### Phase 3: Performance Benchmarks

**File**: `e2e_performance_benchmark.py`

- Response time measurements
- Memory profiling
- Concurrent user simulation
- Scalability testing

---

## Part 5: Test Metrics & Reporting

### Success Metrics

| Category | Target | Weight |
|----------|--------|--------|
| UX Tests Pass Rate | >90% | 30% |
| Function Tests Pass Rate | >95% | 40% |
| Efficiency Tests Pass Rate | >85% | 30% |

### Automated Reporting

```
Test Report Format:
- Summary: X/Y tests passed (Z%)
- By Category: UX, Function, Efficiency breakdown
- Failed Tests: Detailed error logs
- Screenshots: Visual evidence
- Performance: Timing charts
```

---

## Appendix: Test Data Requirements

### Sample Files Needed
- Small FASTQ (1000 reads) for quick tests
- Medium FASTQ (100K reads) for function tests
- Large FASTQ (1M reads) for performance tests
- Sample h5ad for scRNA-seq
- Sample VCF for variant testing
- Sample PDB for structure tests

### Mock Data
- Pre-computed pilot results for demo
- Cached database responses for offline testing
- Sample BibTeX output for validation
