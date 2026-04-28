# CompBioBench Dataset

**Source:** Nair et al. (Genentech/Roche), bioRxiv 2026.04.06.716850  
**Title:** "Agentic systems are adept at solving well-scoped, verifiable problems in computational biology"  
**Date:** April 9, 2026  
**Paper:** https://www.biorxiv.org/content/10.64898/2026.04.06.716850v1  
**Dataset:** https://doi.org/10.5281/zenodo.19443185  
**Code:** https://github.com/Genentech/compbiobench-runner

## Benchmark design

100 tasks, binary correctness scoring, 6 domains:
- Genomics (contaminant detection, enzyme bias in ATAC-seq)
- Transcriptomics (RNA-seq analysis)
- Epigenomics (TF inference from chromatin accessibility)
- Single-cell (Perturb-seq alignment, scRNA-seq demultiplexing)
- Human genetics (ancestry inference, sample swap detection)
- ML for biology (mRNA sequence optimization, ML model inference)

Tasks require: write custom code, install packages, fetch external data, extract a specific numeric/categorical answer.

## Published baselines

| System | Overall | Hardest quartile |
|---|---|---|
| Codex CLI (GPT-5.4) | 83% | 59% |
| Claude Code (Opus 4.6) | 81% | 69% |

## Gap analysis vs BioMate

BioMate's design is complementary but not identical to what CompBioBench tests.

### Where BioMate overlaps
- Workflow routing: genomics (sarek), transcriptomics (rnaseq), single-cell (scrnaseq), epigenomics (chipseq/atacseq)
- Human genetics: raredisease, sarek variant calling
- AI findings panel: partial result interpretation

### Where BioMate has gaps
1. **No ad-hoc code execution** — CompBioBench tasks require writing and running custom Python/R; BioMate uses pre-built Nextflow workflows
2. **No external data fetching** — tasks need to download from SRA/GEO/Ensembl; BioMate expects user-provided files
3. **No specific answer extraction** — CompBioBench expects "what is the p-value for X?"; BioMate produces output files + AI findings summary but not a specific extracted answer
4. **No ML model inference** — designing sequences, running published ML models — BioMate doesn't have this capability

### Estimated BioMate score if run on CompBioBench
- Tasks solvable by workflow routing + AI findings: ~20–30/100
- Remaining tasks require code execution: ~0/70
- **Estimated overall: 20–30%** (vs 80%+ for top agents)

### Path to improvement
The benchmark identifies three capability areas to add to BioMate:
1. **Code execution sandbox** — run Python/R scripts generated from user intent
2. **Data fetching** — SRA toolkit, GEO downloads, Ensembl API
3. **Answer extraction** — after workflow/code runs, extract the specific answer the user asked

## To download dataset

```bash
# Install zenodo_get or use curl
pip install zenodo_get
zenodo_get 10.5281/zenodo.19443185 -o evaluation/datasets/compbiobench/raw/

# Or use the compbiobench-runner
git clone https://github.com/Genentech/compbiobench-runner
```

## Task format (from compbiobench-runner)
Tasks are YAML with fields: `id`, `domain`, `question`, `answer`, `difficulty`, `tools_needed`, `data_sources`.
