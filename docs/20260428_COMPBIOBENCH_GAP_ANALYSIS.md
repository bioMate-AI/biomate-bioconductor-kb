# CompBioBench Gap Analysis
**Date:** 2026-04-28  
**Benchmark:** Nair et al. (Genentech/Roche), bioRxiv 2026.04.06.716850  
**Dataset:** https://doi.org/10.5281/zenodo.19443185  
**Runner:** https://github.com/Genentech/compbiobench-runner

---

## What CompBioBench Tests

100 tasks across 8 domains, scored by binary correctness against a ground-truth answer:

| Domain | Tasks | BioMate coverage |
|---|---|---|
| Single-cell | 21 | Partial (scrnaseq workflow) |
| Genomics | 20 | Partial (sarek, rnaseq) |
| Epigenomics | 20 | Partial (chipseq, atacseq) |
| Transcriptomics | 17 | Partial (rnaseq, DESeq2) |
| Population Genetics | 12 | Low (no specialized workflow) |
| Machine Learning | 7 | None |
| Spatial | 2 | None |
| Structure | 1 | Partial (AlphaFold workflow) |

**Task characteristics:**
- 73/100 require local data files from a 12 GB archive
- 78/100 require internet access (API calls, external data fetching)
- Top skills: Reasoning (65%), Coding (50%), Bioinformatics Tools (43%), API/Web Fetching (42%)

**Agent paradigm:** Claude Code / Codex CLI running in fresh conda environments — agents install packages, write custom Python/R code, fetch data from public APIs (SRA, GEO, Ensembl, UCSC), and extract a specific numerical or categorical answer.

**Published baselines:**
- Codex CLI (GPT-5.4): 83% overall, 59% hardest quartile
- Claude Code (Opus 4.6): 81% overall, 69% hardest quartile

---

## BioMate vs CompBioBench: Capability Gap

### Paradigm mismatch
BioMate is a **workflow orchestration platform** — it routes user intent to pre-built Nextflow workflows, launches them on AWS Batch, and interprets results. CompBioBench tests **ad-hoc code agents** — they receive a question and must figure out how to solve it from scratch with custom code.

These are complementary, not competing:
- CompBioBench: "write Python to compute GC content of this genomic interval" 
- BioMate: "run nf-core/rnaseq on these samples and interpret the results"

### Specific gaps

| Capability | CompBioBench | BioMate today | Path to add |
|---|---|---|---|
| Execute custom Python/R | Required (50/100 tasks) | ✗ None | Code execution sandbox |
| Install packages dynamically | Required | ✗ None | Conda env per session |
| Fetch from SRA / GEO / Ensembl | Required (42/100) | ✗ None | Data fetching agent |
| Run pre-built Nextflow workflow | Not tested | ✓ Core capability | — |
| Answer a specific question from results | Required (all) | Partial (AI findings panel) | Structured answer extraction |
| ML model inference (Borzoi, Enformer) | 7 tasks | ✗ None | ML inference endpoint |
| Population genetics (1000G, ATAC overlap) | 12 tasks | ✗ None | New workflows |

### Estimated BioMate score on CompBioBench
- File-based tasks (73): **~0%** — BioMate doesn't have the data files or code to analyze them
- No-file, internet tasks (27): **~5–10%** — BioMate might answer knowledge/API questions through chat, but cannot execute Ensembl API calls or run custom code
- **Estimated overall: 3–7%** vs 81–83% for top agents

---

## What This Means for BioMate's Development

CompBioBench defines the frontier of what agentic bioinformatics systems can do. BioMate covers a *different but complementary* frontier — structured workflow orchestration at scale, with QC gates, parameter management, and automated remediation.

### To compete on CompBioBench tasks, BioMate needs:

**Priority 1 — Code execution sandbox** (highest ROI)
- Sandboxed Python/R execution environment per session
- Tasks solvable: ~40-50 of the 100 tasks involve pure computation on provided data
- Implementation: Jupyter kernel per session, or subprocess execution with resource limits

**Priority 2 — Public data fetching**
- Ensembl REST API, ClinVar API, UCSC API, GTEx API, SRA toolkit
- Tasks solvable: ~15-20 tasks fetch from these sources
- Implementation: pre-built API clients in ResearchAgent (already started)

**Priority 3 — Structured answer extraction**
- After running code or workflow, extract the specific answer the user asked
- Currently AI findings returns a summary; CompBioBench needs an exact number
- Implementation: "answer extractor" step that parses outputs for the specific value

### BioMate's unique advantages CompBioBench doesn't test
- Parameter pre-filling from natural language (tested in param_prefill benchmark)
- Multi-step workflow orchestration with QC gates and auto-remediation
- AWS Batch scaling for large genomics runs
- Audit trail, reproducibility, and provenance tracking
- Clinical trial design and IND document generation

---

## Tasks BioMate Can Attempt Now (No File Needed)

27/100 tasks require no local data files. BioMate could attempt these via its chat interface:

| Category | Count | Examples |
|---|---|---|
| Ensembl/ClinVar API lookup | ~8 | Gene ID conversion, variant annotation |
| Sequence retrieval from public genome | ~5 | GC content, promoter sequences |
| Parameter/count lookup (knowledge) | ~5 | Model parameter counts (Enformer, Borzoi) |
| 1000 Genomes data access | ~3 | Genotype retrieval |
| GTEx expression query | ~1 | APOE expression in Brain_Cortex |
| Computational (no data) | ~5 | RNA secondary structure (ViennaRNA) |

**Next step:** Create a curated `tasks_no_file.yaml` with the 27 tasks, build an adapter that submits them to BioMate chat, and measure the partial score. This gives a concrete number to track improvement as we add API clients and code execution.

---

## Files

- Dataset TSV: `evaluation/datasets/compbiobench/raw/compbiobench.v1.tsv`
- Data archive: `evaluation/datasets/compbiobench/raw/compbiobench_v1_data.tar` (downloading)
- Adapter: `evaluation/adapters/compbiobench_adapter.py`
- Runner: `evaluation/runners/run_compbiobench.py`
- README: `evaluation/datasets/compbiobench/README.md`
