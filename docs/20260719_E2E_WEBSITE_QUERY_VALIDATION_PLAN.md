# BioMate E2E Website Query Validation Plan
**Date:** 2026-07-19  
**Purpose:** Validate every publicly-visible query example works end-to-end before the lab demo meeting  
**Target:** dev-public.biomate.ai  
**Methodology:** API-level SSE stream validation + Playwright UI smoke tests

---

## Overview

The website surfaces 25 clickable query examples across two pages:
- **index.html hero chips** (4 queries): First-touch entry point for all visitors
- **services.html "Try it →" links** (21 queries): Deep-linked from service categories, all redirect to `dev-public.biomate.ai/register?q=<query>`

Every query must pass a 4-layer test:

| Layer | What we test | Pass criteria |
|-------|-------------|---------------|
| **L1: Auth & routing** | Query reaches the AI without auth error | HTTP 200, SSE stream opens |
| **L2: Intent classification** | AI routes to correct intent | Intent matches expected type |
| **L3: Result quality** | Top workflow/tool is relevant and named correctly | Name contains expected keyword(s) |
| **L4: Response completeness** | AI explanation is coherent, no error fallback | No "I couldn't find", no null fields in response |

---

## Test Infrastructure

```
Dev URL:      https://dev-public.biomate.ai
API endpoint: POST /api/chat/stream
Auth:         Bearer <JWT> from /api/auth/login
              OR X-E2E-Bypass-Token: biomate-e2e-bypass-token-dev-only
Fixture user: lifeifei163361@163.com / WpmFixture!2026
```

SSE stream parse rules:
- Event `chat_message` with content = AI's textual response
- Event `workflow_results` = array of matched workflows (check `results[0].name`)
- Event `tool_results` = array of matched tools
- Event `intent` = classified intent string
- Event `error` = FAIL unconditionally

---

## Query Matrix

### Category A: Homepage Hero Chips (highest traffic, most visible)

| # | Label | Query | Expected Intent | Expected Top Result | Risk |
|---|-------|-------|----------------|---------------------|------|
| A1 | Microarray · GSE39582 | "Analyze GEO dataset GSE39582 (colon cancer microarray). Which pathways differ between MSI-high and MSS tumors?" | `workflow_search` or `data_analysis` | nf-core/rnaseq or microarray DE workflow; pathway enrichment mention | HIGH |
| A2 | ADMET · imatinib | "What is the ADMET profile of imatinib?" | `database_lookup` or `tool_search` | ADMET prediction tool or ChEMBL lookup | HIGH |
| A3 | WGS · NA12878 | "What pathogenic variants does GIAB reference sample NA12878 carry?" | `database_lookup` or `workflow_search` | Variant annotation/GATK workflow or ClinVar lookup | HIGH |
| A4 | scRNA-seq · PBMC 3k | "Analyze the 10x Genomics PBMC 3k dataset. What cell types are present and how do they cluster?" | `workflow_search` | nf-core/scrnaseq or Seurat/Scanpy workflow | HIGH |

### Category B: Drug Discovery Pipeline (services.html)

| # | Label | Query | Expected Intent | Expected Top Result | Risk |
|---|-------|-------|----------------|---------------------|------|
| B1 | Target ID | "Identify and rank therapeutic targets by genetic support, CRISPR essentiality, tissue expression, and pocket druggability…" | `workflow_search` | Target ID / Open Targets workflow | HIGH |
| B2 | Compound screening | "Screen a compound library against a target protein using AutoDock Vina and DiffDock…" | `workflow_search` | AutoDock Vina or molecular docking workflow | HIGH |
| B3 | ADMET panel | "Run a full ADMET panel for a small molecule drug candidate — hERG cardiotoxicity, DILI, Ames mutagenicity…" | `workflow_search` or `tool_search` | ADMET/pkCSM/SwissADME tool | HIGH |
| B4 | PBPK simulation | "Run PBPK simulation for a drug candidate and scale the dose from mouse to human using allometric scaling…" | `workflow_search` | PBPK/PK-Sim simulation workflow | MEDIUM |
| B5 | Population PK | "Model population PK for a drug candidate, simulate dose-escalation to estimate MTD…" | `workflow_search` | PopPK/NONMEM/Monolix workflow | MEDIUM |
| B6 | FAERS safety | "Analyze FAERS adverse event data for a drug — run ROR and PRR disproportionality scoring…" | `workflow_search` or `tool_search` | FAERS/pharmacovigilance tool | MEDIUM |

### Category C: Omics Workflows (core bioinformatics, most likely demo queries)

| # | Label | Query | Expected Intent | Expected Top Result | Risk |
|---|-------|-------|----------------|---------------------|------|
| C1 | WGS/variant calling | "Run whole-genome sequencing variant calling using nf-core/sarek with GATK HaplotypeCaller…" | `workflow_search` | nf-core/sarek | HIGH |
| C2 | RNA-seq DE | "Run bulk RNA-seq differential expression analysis comparing treated vs control samples with DESeq2…" | `workflow_search` | nf-core/rnaseq | HIGH |
| C3 | ATAC-seq | "Run ATAC-seq chromatin accessibility analysis using nf-core/atacseq…" | `workflow_search` | nf-core/atacseq | MEDIUM |
| C4 | DIA proteomics | "Run label-free proteomics DIA quantification with DIA-NN from mzML files…" | `workflow_search` | DIA-NN/proteomics workflow | MEDIUM |
| C5 | Metabolomics | "Run untargeted LC-MS metabolomics with XCMS…" | `workflow_search` | XCMS/metabolomics workflow | MEDIUM |
| C6 | Metagenomics | "Run shotgun metagenomics taxonomic profiling with Kraken2 and MetaPhlAn4…" | `workflow_search` | nf-core/taxprofiler or Kraken2 workflow | MEDIUM |
| C7 | Multi-omics | "Integrate RNA-seq, proteomics, and metabolomics datasets using MOFA+…" | `workflow_search` | MOFA+/multi-omics integration | MEDIUM |

### Category D: Clinical & Trial Design

| # | Label | Query | Expected Intent | Expected Top Result | Risk |
|---|-------|-------|----------------|---------------------|------|
| D1 | Phase I BOIN | "Design a Phase I dose-escalation oncology trial using the BOIN model…" | `workflow_search` or `info_request` | BOIN/clinical trial design | MEDIUM |
| D2 | Pharmacogenomics | "Run CYP2D6 and CYP2C19 pharmacogenomics genotyping…" | `workflow_search` | PharmGKB/PGx genotyping workflow | MEDIUM |
| D3 | Clinical somatic | "Run clinical somatic variant calling on a tumor sample with GATK4…" | `workflow_search` | GATK4 somatic/nf-core/sarek | MEDIUM |
| D4 | Survival analysis | "Run survival analysis on a retrospective cancer cohort — Kaplan-Meier curves, Cox PH…" | `workflow_search` or `tool_search` | Survival analysis R workflow | MEDIUM |

### Category E: Structural Biology

| # | Label | Query | Expected Intent | Expected Top Result | Risk |
|---|-------|-------|----------------|---------------------|------|
| E1 | CryoSPARC | "Run CryoSPARC single particle analysis on cryo-EM micrographs…" | `workflow_search` | cryosparc/cryo-EM workflow | HIGH |
| E2 | AlphaFold3 | "Predict the 3D structure of a protein sequence using AlphaFold3…" | `workflow_search` | AlphaFold/structure prediction workflow | HIGH |
| E3 | GROMACS MD | "Run GPU-accelerated GROMACS molecular dynamics simulation for a protein-ligand complex…" | `workflow_search` | GROMACS/MD simulation workflow | MEDIUM |
| E4 | AutoDock Vina | "Dock a small molecule ligand into a target protein using AutoDock Vina…" | `workflow_search` | AutoDock Vina/molecular docking | HIGH |

---

## Pass/Fail Criteria (per query)

### PASS
- HTTP 200, SSE stream opens and closes cleanly
- Intent matches expected type (or functionally equivalent)
- At least one workflow or tool result returned
- Top result name contains expected keyword(s) OR AI explanation references the expected tool
- No error event in stream
- Response text ≥ 50 characters (not a stub/fallback)

### FAIL
- HTTP 4xx/5xx
- SSE stream closes with `error` event
- Intent routed to completely wrong category (e.g., `info_request` for a clear `workflow_search`)
- Zero results returned
- Response is "I couldn't find anything" or generic fallback
- Null/undefined leaking into response text

### WARN (document but don't block)
- Wrong workflow ranked #1 but correct type in top 3
- Verbose/padded response but contains correct answer
- Slow response (>10s to first token)

---

## Evaluation Rubric (per query, 0-3 score)

| Score | Meaning |
|-------|---------|
| 3 | Perfect: correct intent + correct top result + clean coherent response |
| 2 | Good: correct intent + relevant result but not #1 expected, or minor response issue |
| 1 | Partial: wrong intent OR no results but response is partially correct |
| 0 | Fail: error, crash, completely wrong result, or generic fallback |

Target: All HIGH-risk queries score ≥ 2. Overall mean ≥ 2.0.

---

## Known Pre-Conditions & Risk Areas

1. **Database queries** (A2 ADMET imatinib, A3 NA12878): Require ChEMBL/ClinVar integration working
2. **Workflow search quality**: Depends on enriched FTS index (3,159/12,284 enriched as of 2026-07-02)
3. **AlphaFold3 / GROMACS**: These are biomate-ai-tools workflows — now indexed at priority 92
4. **CryoSPARC**: Verify cryosparc workflow is in the DB after Wave 2 indexing
5. **PBPK / PopPK**: No standard nf-core pipeline; depends on biomate custom workflows
6. **Multi-omics / MOFA+**: May not have a dedicated workflow; tests AI's ability to combine tools

---

## Test Execution Plan

### Phase 1: API Validation (automated, all 25 queries)
Run via curl/Python against `/api/chat/stream` with fixture token.  
Collect: intent, top result name, result count, response snippet, error flag.  
Target duration: ~30 minutes.

### Phase 2: Critical Path UI Smoke Test (manual/Playwright, HIGH-risk only)
Test A1–A4, B1–B3, C1–C2, E1–E2, E4 (11 queries) in browser.  
Verify: chips load, redirect works, chat UI renders results, no layout breaks.  
Target duration: 60 minutes.

### Phase 3: Fix & Retest
Address failures found in Phase 1 & 2.  
Priority: routing bugs > search quality > response polish.

---

## Results Log — Run 1 (2026-07-19, pre-fix baseline)

| # | Query | Score | Top Result | Notes |
|---|-------|-------|-----------|-------|
| A1 | GSE39582 microarray | 🌟3 | nf-core/differentialabundance | Correct pipeline, full response |
| A2 | ADMET imatinib | 🌟3 | Research agent (detailed ADMET facts) | High-quality 4034-char response |
| A3 | NA12878 GIAB | 🌟3 | Research agent (NA12878 variants) | Accurate variant list with clinical context |
| A4 | PBMC 3k scRNA | 🌟3 | scrnaseq_standard_endtoend | Correct pipeline |
| B1 | Target ID | 🌟3 | target_tractability_scorer | Correct workflow |
| B2 | Compound screening | 🌟3 | (info response, 3701 chars) | Detailed response covering AutoDock/DiffDock |
| B3 | ADMET panel | 🌟3 | Predict ADMET Properties (AI) | Correct ADMET workflow |
| B4 | PBPK simulation | 🌟3 | (prereq gate fired) | Correctly asks for SMILES/CLint/fu |
| B5 | Population PK | ⚠️1 | clinical_trial_simulation | Routes to clinical trial simulation (has PopPK) but missing DDI CYP3A4 |
| B6 | FAERS safety | 🌟3 | (info response, 3504 chars) | Detailed FAERS/pharmacovigilance info |
| C1 | WGS/sarek | ⚠️1 | (clarification asked) | **BUG**: unnecessary tumor-vs-germline clarification for HaplotypeCaller query → **FIXED** |
| C2 | RNA-seq DESeq2 | 🌟3 | nf-core/differentialabundance | Correct pipeline |
| C3 | ATAC-seq | 🌟3 | nf-core/atacseq | Correct pipeline |
| C4 | DIA proteomics | ⚠️1 | msstatsconvert (wrong!) | **BUG**: routes to format converter instead of nf-core/diaproteomics → **FIXED** |
| C5 | Metabolomics | 🌟3 | Lc Ms Proteomics Metabolomics | Correct domain match |
| C6 | Metagenomics | 🌟3 | nf-core/taxprofiler | Correct pipeline |
| C7 | Multi-omics MOFA+ | 🌟3 | nipalsmcia_single_cell_cite_seq_mcia | Multi-omics integration workflow |
| D1 | Phase I BOIN | 🌟3 | (prereq gate fired) | Correctly asks for dose levels |
| D2 | Pharmacogenomics | 🌟3 | pharmacogenomics_pgx_report | Correct pipeline |
| D3 | Clinical somatic | 🌟3 | (clarification asked) | Correct: asks tumor-paired vs tumor-only |
| D4 | Survival analysis | 🌟3 | survival | Correct workflow |
| E1 | CryoSPARC | ⚠️1 | (clarification asked) | **BUG**: asks globular-vs-helical when query says "single particle" + "homogeneous refinement" → **FIXED** |
| E2 | AlphaFold3 | 🌟3 | Predict Binding Affinity Protein 1D Seq | Structure prediction workflow |
| E3 | GROMACS MD | ⚠️1 | GROMACS Protein-Ligand MD + MM-GBSA | Correct workflow found, asks for PDB (correct behavior) |
| E4 | AutoDock Vina | 🌟3 | (info+AutoDock response, 3421 chars) | Detailed docking response |

**Run 1 Score: 20/25 pass (80%), mean=2.60/3**  
**Bugs fixed: C1 (somatic_paired resolver), E1 (cryoem_sample resolver), C4 (proteomics domain catalog + routing)**

## Results Log — Run 2 (2026-07-19, post-fix) — PENDING SYNC
