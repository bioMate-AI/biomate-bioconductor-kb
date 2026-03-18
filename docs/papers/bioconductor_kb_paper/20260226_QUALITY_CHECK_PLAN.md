# Bioconductor Knowledge Base — Quality Check Plan
**Date**: 2026-02-26
**Scope**: galaxy_ai_tools.db — 2,241 Bioconductor packages, 28,485 workflow steps, 50,959 function annotations
**Goal**: Establish publication-grade quality evidence for paper submission

---

## 1. Current State Summary

| Metric | Value |
|--------|-------|
| Total Bioconductor packages attempted | 2,241 |
| Packages with workflow steps in DB | 1,970 (87.9%) |
| Total workflow step records | 28,485 |
| Total primary function annotations | 50,959 |
| EDAM ontology coverage | 94.7% |
| Biocontainer URL coverage | 98.8% |
| Software DOI coverage | 100% |
| Provenance (vignette URL + git commit) | 2,106+ packages |

---

## 2. Quality Dimensions to Evaluate

### 2.1 Correctness (Ground Truth Comparison)
*Are the extracted steps actually correct for each package?*

**Sampling strategy**: Stratified random sample of 200 packages
- 50 high-step packages (>20 steps)
- 50 medium-step packages (5–20 steps)
- 50 low-step packages (1–5 steps)
- 50 zero-step packages (coverage gap analysis)

**Check per package**:
- [ ] Do extracted function names match the actual package exports?
- [ ] Are input/output types correctly inferred?
- [ ] Is the step ordering logical (follows vignette narrative)?
- [ ] Are key_params relevant to actual function signatures?
- [ ] Is sample_code syntactically valid R?

**Tool**: `python3 bioconductor_skill/skill_generation/quality_check.py --sample 200 --stratified`
(Script to be created — see Section 6)

### 2.2 Completeness (Coverage Analysis)
*Do the 271 zero-step packages represent unavoidable gaps or fixable errors?*

**Sub-categories to validate**:
| Category | Expected Count | Action |
|----------|----------------|--------|
| Data/annotation-only packages | ~87 | Mark `not_suitable=["no_workflow"]` — expected gap |
| PDF-only documentation | ~45 | Attempt PDF text extraction (pdfplumber); if fails, mark `not_suitable=["pdf_only"]` |
| GUI-only packages (no scriptable API) | ~15 | Mark `not_suitable=["gui_only"]` |
| Not on Bioconda (container gap only) | 28 | Keep; fill container via dockerhub search |
| Fixable stubs (undiscovered books) | ~10 | Manual rescue |

**Check**: Run `SELECT name, priority_score FROM tools WHERE nfcore_metadata LIKE '%"vignette_workflows": []%' ORDER BY priority_score DESC LIMIT 20` and inspect each.

### 2.3 Semantic Quality (EDAM Alignment)
*Are the EDAM operation annotations semantically accurate?*

**Method**: Sample 100 packages with EDAM annotations
- Compare `edam_operations` JSON array to manually assigned EDAM terms
- Compute precision@1 (is the top EDAM term correct?) and recall
- Use EDAM OWL hierarchy for partial credit (parent term counts as 0.5)

**Domain expert reviewers needed**:
- Genomics/sequencing expert (RNA-seq, WGS, ChIP-seq categories)
- Structural biology expert (AlphaFold, cryo-EM related packages)
- Proteomics expert (mass spectrometry, LC-MS packages)
- Statistical/ML expert (Bioconductor stats packages)

### 2.4 Executable Quality (Step Runnability)
*Can the extracted sample_code actually run?*

**Automated test**: For 50 packages with sample_code, attempt R execution:
```bash
for pkg in sample_50:
    Rscript -e "library($pkg); $step.sample_code" 2>&1 | check_for_errors
```
**Target**: ≥70% of steps should run without fatal errors on sample data
**Note**: Many steps depend on data files; count "data not found" as partial success

### 2.5 Retrieval Quality (Task-to-Workflow Matching)
*When a user asks a bioinformatics question, does the KB retrieve the right package?*

**Benchmark**: Create 50 query pairs: (natural language task description, expected package/step)
Examples:
- "Identify differentially expressed genes between two conditions" → DESeq2 / edgeR
- "Cluster single-cell RNA-seq data using graph-based community detection" → Seurat / scran
- "Annotate genomic peaks with nearest gene features" → ChIPseeker

**Metric**: MRR@5 (Mean Reciprocal Rank), Hit@1, Hit@5
**Baseline**: bio.tools keyword search, raw Bioconductor package search

### 2.6 Data Freshness and Provenance
*Is the data traceable and up-to-date?*

**Checks**:
- [ ] All `vignette_url` links resolve (HTTP 200) — run link checker on 200 sample
- [ ] `git_commit` hashes are valid on corresponding GitHub repos
- [ ] DOI links resolve via CrossRef API
- [ ] Version numbers match current Bioconductor 3.20 release

---

## 3. Domain Expert Review Panel

We need at least one expert per major Bioconductor category for the paper's evaluation section.

| Specialty | Target Packages | Review Scope | Where to Find |
|-----------|----------------|--------------|---------------|
| Transcriptomics (RNA-seq, scRNA-seq) | DESeq2, edgeR, limma, Seurat, Monocle | 50 packages | Co-author from RNA-seq community (e.g. bioc-devel list) |
| Epigenomics (ChIP-seq, ATAC-seq, methylation) | ChIPseeker, DiffBind, minfi, BSseq | 30 packages | ENCODE DCC contacts, ENCODE4 consortium |
| Genomic Variants (WGS, WES, GWAS) | VariantAnnotation, GenomicRanges, snpStats | 30 packages | GATK team contacts, Bioconductor core |
| Proteomics (LC-MS, mass spec) | MSnbase, msqrob2, CAMERA | 20 packages | EBI PRIDE contacts, Perseus/MaxQuant team |
| Microbiome / Metagenomics | phyloseq, microbiome, metagenomeSeq | 20 packages | Human Microbiome Project contacts |
| Structural Biology (cryo-EM, protein) | Bio3D, Rpdb | 10 packages | Internal (cryo-EM paper co-authors) |
| Machine Learning / Imaging | MLInterfaces, EBImage | 20 packages | Bioconductor core team |

**Review protocol per expert**:
1. Provide 20–50 package entries as JSON + rendered HTML report
2. Score each step: 3=Correct, 2=Partially correct, 1=Minor errors, 0=Wrong
3. Flag: missing critical steps, incorrect function names, wrong input/output types
4. Rate overall workflow quality: A/B/C/D
5. Estimated time: 2–4 hours per reviewer for 20 packages

---

## 4. Automated Quality Scripts to Create

### 4.1 Syntax Validator (`validate_step_syntax.py`)
```python
# Check every step's sample_code for R syntax validity
# Use rpy2 or subprocess Rscript --parse
# Report: % syntactically valid, common error types
```

### 4.2 Function Name Validator (`validate_function_names.py`)
```python
# For each (package, function_name) pair:
# Query CRAN/Bioconductor namespace via R: getNamespaceExports(pkg)
# Check if function exists in package
# Report: true positive rate, common false positives (tidyverse imported fns, etc.)
```

### 4.3 Link Checker (`check_provenance_links.py`)
```python
# For each vignette_url + DOI:
# HTTP HEAD request with timeout=10s
# Report: % 200 OK, % 301/302 redirect, % 404/gone
```

### 4.4 Coverage Report (`generate_coverage_report.py`)
```python
# For each Bioconductor package on r-universe:
# Check if in DB, has steps, has EDAM, has Biocontainer
# Generate per-category heatmap table
```

### 4.5 Retrieval Benchmark (`run_retrieval_benchmark.py`)
```python
# 50 curated queries × gold standard package
# Test: UnifiedToolSearch.search(query) → rank of gold package
# Compute MRR@5, Hit@1, Hit@5
```

---

## 5. Quality Check Timeline

| Week | Activity | Output |
|------|----------|--------|
| Week 1 | Build automated validators 4.1-4.4 | Scripts + initial reports |
| Week 1 | Identify domain experts, send invitations | 7 expert invitations sent |
| Week 2 | Run syntax + function name validation | Error reports, fix top issues |
| Week 2 | Run link checker, fix broken provenance | Updated DB entries |
| Week 2-3 | Expert reviews (async, 2-4h each) | Scoring sheets per domain |
| Week 3 | Run retrieval benchmark (4.5) | MRR@5, Hit@1/Hit@5 numbers |
| Week 3 | Aggregate scores, compute inter-rater agreement | Cohen's kappa, quality table |
| Week 4 | Fix systematic errors found by experts | Updated DB, re-run validators |
| Week 4 | Final quality report + paper integration | Quality evidence section |

---

## 6. Acceptance Criteria (for paper)

The KB is publication-ready when ALL of the following hold:
- [ ] Expert review precision (steps correct or partially correct): **≥ 85%**
- [ ] Function name true positive rate: **≥ 90%**
- [ ] EDAM annotation precision@1: **≥ 80%**
- [ ] Provenance link validity: **≥ 95%** (HTTP 200 or 301)
- [ ] Retrieval Hit@5 on 50-query benchmark: **≥ 75%**
- [ ] Sample code syntax validity: **≥ 70%**

---

## 7. Known Issues to Fix Before Review

Based on the yulab book extraction work and audit:

1. **Noise functions in steps**: Some steps have `primary_functions = ['library', 'install', 'set.seed']` only — these are boilerplate. Fix: add to STRICT_NOISE filter.
2. **Overly long steps**: OncoSimulR has 384 steps — likely over-split. Fix: merge steps that are subsections of same analysis section.
3. **Generic step names**: Steps named "Data" or "Analysis" without specificity. Fix: use section heading + first function name.
4. **Missing output types**: ~30% of steps have `output_types = []`. Fix: extend TYPE_SIGNATURES dict with more patterns.
5. **Duplicate functions**: Some steps list the same function 3× from code blocks. Fix: dedup `primary_functions` list.
6. **limma/edgeR cross-contamination**: Both packages extracted from same limmaWorkflow.html — ensure function attribution is correct.
