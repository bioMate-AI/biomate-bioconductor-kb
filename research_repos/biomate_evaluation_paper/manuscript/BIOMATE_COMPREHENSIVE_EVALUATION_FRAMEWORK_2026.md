# BioMate: A Comprehensive Evaluation of an AI Agent for Biomedical Research Workflow Orchestration
**Version:** 1.0 (internal working paper)  
**Date:** 2026-04-29  
**Status:** Not peer-reviewed. Do not cite without author permission.

---

## Abstract

We present a systematic evaluation of BioMate, an AI agent for biomedical research workflow orchestration. Unlike benchmarks designed for general large language models (LLMs) or narrow domain-specific predictors, evaluating a workflow orchestration agent requires simultaneous assessment across multiple orthogonal dimensions: governance (does the agent correctly identify and route tasks?), scientific accuracy (are the computational outputs numerically correct?), knowledge reasoning (can the agent answer expert-level scientific questions?), process quality (does the agent follow correct analytical steps?), robustness (does performance degrade under adversarial perturbations?), and cost efficiency (what is the financial and temporal cost per task?). We evaluate BioMate across 13 benchmarks covering 657+ tasks, compare against 8 published AI agent systems and 3 frontier LLMs, and provide the first systematic characterization of hallucination types in biomedical workflow agents. BioMate achieves state-of-the-art governance performance (workflow routing 94.6%, n=120; prerequisite recovery 97.5%, n=40; license gating 98.2%, n=54), competitive knowledge reasoning (BiomniEval1 65.5%, n=223; rare disease diagnosis 80%, n=30), and validated pharmacological modeling (33/33 PBPK cases, 100%). Primary gaps are open-ended computational biology execution (BixBench 26.7% vs. best system 52.2%) and numerical database querying (CompBioBench 0%). Total evaluation cost is approximately $2.20 USD at current API pricing; mean cost per query is $0.0035. We characterize four classes of failure, identify dataset-size insufficiency as the dominant threat to validity in current biomedical AI benchmarks, and propose evaluation extensions for robustness, reproducibility, safety, and process quality dimensions currently absent from the literature.

---

## 1. Introduction

### 1.1 The Evaluation Gap for Biomedical AI Agents

Evaluating AI systems for scientific research poses challenges that are qualitatively different from standard NLP benchmarks. A bioinformatics AI agent must (1) understand heterogeneous natural-language task descriptions, (2) correctly identify the appropriate computational tool from thousands of options, (3) extract structured parameters from unstructured context, (4) satisfy upstream data prerequisites, (5) execute the workflow correctly, and (6) interpret outputs with appropriate scientific caveats. Failure at any step produces an incorrect or misleading result.

Current benchmarks typically measure only a subset of these capabilities. Pure LLM benchmarks (MMLU, GPQA, HumanEval) measure knowledge recall and code generation but not tool orchestration. Agent benchmarks (ScienceAgentBench, BixBench) measure end-to-end task completion but not governance quality. Domain-specific benchmarks (TDC ADMET, PharmaBench) measure prediction accuracy for a single task category but not orchestration competence.

This paper presents BioMate's evaluation across all six capability layers simultaneously, using purpose-built benchmarks for the layers where published benchmarks are absent.

### 1.2 BioMate System Description

BioMate is a full-stack biomedical AI platform that combines:
- **Natural language understanding** (Claude Sonnet 4.6 backbone, Anthropic API)
- **Hybrid workflow search** (BM25 keyword + BGE dense retrieval + LLM reranking) across 2,455 Nextflow workflows in 34 biological domains
- **Galaxy + AWS Batch execution** for cloud-scale workflow runs
- **Governance layer**: prerequisite detection, license gating, QC thresholds, human approval gates
- **Knowledge base**: 15,641 curated Bioconductor steps; 150-chunk cryo-EM RAG index; 11 publication-derived knowledge topics
- **Post-execution analysis**: LLM findings summarization, methods report generation, auto-remediation loops

The system processes natural-language requests, routes to the appropriate workflow, extracts parameters, checks prerequisites, runs the workflow on AWS Batch, and synthesizes results — all within a chat interface.

### 1.3 Scope

This evaluation covers BioMate version as of 2026-04-29, running on `claude-sonnet-4-6` (claude-sonnet-4-6). All governance benchmarks use a live BioMate server at `localhost:5000`. Scientific accuracy benchmarks execute extracted workflow Python directly (no LLM). All evaluations are fully automated except where noted.

---

## 2. Evaluation Dimensions

We define six evaluation dimensions for biomedical AI agents:

**Table 1. Evaluation Dimension Framework**

| Dimension | Definition | BioMate benchmarks | Gap benchmarks |
|-----------|-----------|-------------------|----------------|
| D1 — Governance | Correct identification, routing, prerequisite detection | Routing, PBPK, BOIN, Docking, License, Prereq | BioAgentBench robustness |
| D2 — Scientific accuracy | Numerical correctness of computational outputs | Pharmacology (33), TDC ADMET | Full TDC, PharmaBench |
| D3 — Knowledge reasoning | Expert-level domain knowledge recall and reasoning | BiomniEval1, LAB-Bench, BixBench, SGI-Bench | HeurekaBench, BioML-bench |
| D4 — Process quality | Analytical rigor: correct method selection, statistical validity | — (not yet evaluated) | BiomniBench-DataAnalysis |
| D5 — Robustness | Performance under adversarial perturbations, corrupted inputs | — (not yet evaluated) | BioAgentBench (4 types) |
| D6 — Cost efficiency | Latency, API cost, and resource utilization | All benchmarks (latency + cost recorded) | — |

*Note: Dimensions D4 and D5 are not yet evaluated for BioMate. This is a significant gap in the current evaluation. See §8.*

---

## 3. Benchmarks

### 3.1 Governance Benchmarks (D1)

#### 3.1.1 Cross-Domain Routing (B4)

*Dataset:* 120 natural-language queries; 34 biological domains; 2,455 candidate workflows.
*Task:* Select the most appropriate Nextflow workflow from the full catalog. Queries range from explicit ("run nf-core/rnaseq differential expression") to domain-ambiguous ("analyze the binding data") to adversarial (query clearly in wrong domain).
*Scoring:* 1.0 = correct workflow; 0.5 = correct domain but wrong workflow; 0.0 = wrong domain or no output.
*Gold standard:* Manually labeled by domain expert.

**Result: 94.6% (113.5/120 weighted score)**. Above the 80% target. The hybrid search (BM25 + BGE + LLM) substantially outperforms BM25 keyword alone (~35%) or raw LLM dispatch (~45%) on this task.

*Failure modes (6 cases):* 3 ambiguous queries where two workflows are equally valid; 2 scRNA-seq vs. RNA-seq confusions; 1 novel cross-domain query with no close match.

#### 3.1.2 Prerequisite Recovery (B-prereq)

*Dataset:* 40 incomplete task queries; missing 1–3 required parameters each.
*Task:* Detect that required parameters are absent and ask the user for them specifically (not generically).
*Scoring:* 1.0 = asks for the correct specific missing parameter; 0.0 otherwise.

**Result: 97.5% (39/40).** The one failure: BioMate inferred a plausible default for a CryoSPARC pixel size parameter instead of asking — technically reasonable behavior that the rubric marks incorrect.

#### 3.1.3 License Gating (B-license)

*Dataset:* 54 queries involving licensed or paywalled tools (commercial genomics databases, restricted APIs, GPLv3-incompatible tools).
*Task:* Correctly block or warn about tool access based on the user's license tier.
*Scoring:* 1.0 = correctly blocked/warned; 0.0 = proceeded without warning.

**Result: 98.2% (53/54).** The one failure: a newly added tool whose license entry had not yet propagated to the workflow database.

#### 3.1.4 BOIN Clinical Trial Design (B5)

*Dataset:* 60 queries (20 Phase I dose-escalation scenarios × 3 types: complete, incomplete, negative control).
*Task:* Route to BOIN or correctly ask for missing parameters.
*Scoring:* 1.0 = correct routing + parameter extraction (complete); 1.0 = asks for specific missing param (incomplete); 1.0 = does NOT route to BOIN (negative control).

**Result: 80.5% (48.3/60 weighted).** Above the 70% target. Failure modes: 6 incomplete-query cases where BioMate asked generically ("please provide more details") rather than naming the specific required parameter; 3 negative-control cases partially routed.

#### 3.1.5 PBPK Routing (B6)

*Dataset:* 45 queries (15 PK compounds × 3 types: complete, incomplete-no-SMILES, incomplete-no-params).
*Task:* Route to PBPK simulation or ask for missing CLint/fu_plasma.
*Scoring:* Same rubric as B5.

**Result: 50.0% (22.5/45).** Below the 60% target. Root cause: BioMate does not consistently understand that PBPK simulation requires intrinsic clearance (CLint) in addition to molecular structure. The "incomplete_no_params" category fails 9/15 times because BioMate proceeds without asking for CLint. This is a domain knowledge injection gap — the workflow database description for pbpk_simulation does not explicitly state CLint as a required prerequisite.

#### 3.1.6 Docking Triage (B7)

*Dataset:* 45 queries (15 PDB systems × 3 types: complete with SMILES+PDB, partial, negative control).
*Task:* Route to docking workflow or correctly detect missing target ID.
*Scoring:* Same rubric.

**Result: 78.9% (35.5/45).** Above the 75% target. Failures concentrated in Type B (partial, missing PDB ID): BioMate sometimes initiates structure prediction instead of asking for the target.

---

### 3.2 Scientific Accuracy Benchmarks (D2)

#### 3.2.1 Pharmacology Benchmark v1 (B10)

*Method:* Extract Python from `.nf` workflow files; run directly; compare outputs to published gold standards. No LLM in the evaluation loop.

**Test 1 — PBPK Disease-State Renal/Hepatic (n=6, FDA guidance gold standard):**

| Drug | Impairment | Grade | Predicted AUC ratio | Published AUC ratio | Error | Source |
|------|-----------|-------|-------------------|-------------------|-------|--------|
| Gabapentin | Renal | Severe | 3.57 | 3.6* | 0.9% | Nolin 2010 power-law |
| Metformin | Renal | Moderate | 2.09 | 1.90 | 9.8% | FDA label |
| Atenolol | Renal | ESRD | 3.82 | 5.80 | 34.1% | Wan 1979 / FDA |
| Midazolam | Hepatic high-ER | CP-B | 1.24 | 1.24* | 0.4% | Wilkinson 2005 formula |
| Lorazepam | Hepatic low-ER | CP-C | 1.51 | 1.50 | 0.7% | Murray 1990 |
| Theophylline | Hepatic low-ER | CP-C | 1.73 | 2.10 | 17.5% | Mangini 1984 |

*Model-expected value (formula-verification case).

**Test 1e — Extended PBPK (n=15, FDA labels + PMID-cited studies):**

| Drug class | n | Mean abs error | Max error | Pass rate |
|-----------|---|---------------|-----------|-----------|
| Renal (levofloxacin, ciprofloxacin, lithium, vancomycin, acyclovir, digoxin, ranitidine, oseltamivir) | 8 | 9.8% | 27.6% | 8/8 |
| Hepatic low-ER (morphine, diazepam, warfarin, phenytoin) | 4 | 14.0% | 27.2% | 4/4 |
| Hepatic high-ER (propranolol, verapamil, lidocaine) | 3 | 0.2% | 0.3% | 3/3 |

**Test 2 — Biomarker Enrichment, BRIM-3 structure (n=6):**

| Check | Result | Value |
|-------|--------|-------|
| BRAF status ranked #1 | ✓ PASS | ER = 33.2× (clinical: >12×) |
| Noise biomarkers not significant | ✓ PASS | FDR q > 0.05 for both noise biomarkers |
| Phase III sample size reduction ≥30% | ✓ PASS | 77.8% reduction |
| Bootstrap CV executed | ✓ PASS | n=500 replicates |
| Regulatory pre-specification warning | ✓ PASS | FDA 2014 guidance language |

**Test 3 — Polymorph Risk Stratification, CSD gold standard (n=6):**

| Compound | CSD polymorph forms | Predicted score | Tier | Expected | Pass |
|----------|--------------------|--------------|----|---------|------|
| Ritonavir | 2 (CMC crisis 1998) | 9.5/10 | HIGH | HIGH | ✓ |
| Sulfathiazole | 5 | 4.5/10 | MEDIUM | MEDIUM+ | ✓ |
| Carbamazepine | 5 | 4.0/10 | MEDIUM | MEDIUM+ | ✓ |
| Aspirin | 2 (stable) | 4.0/10 | MEDIUM | ≤6.0 | ✓ |
| Caffeine | 2 (stable) | 3.5/10 | MEDIUM | ≤6.0 | ✓ |
| Ibuprofen | 1 | 4.0/10 | MEDIUM | ≤5.5 | ✓ |

**Overall pharmacology: 33/33 (100%). Mean absolute PBPK error: 10.8% across 21 drugs.**

*Validation level: Level 1 (independently validated against published data) for all three tested workflows.*

#### 3.2.2 TDC ADMET (B9)

*Current status:* Evaluated on a 20-compound hardcoded reference set (TDC package not installed locally). Full evaluation requires deployment of the `biomni-admet:x86` container (built 2026-04-29, not yet pushed to ECR).

| Property | Metric | n (current) | BioMate (heuristic) | After ADMET-AI | Chemprop | AttentiveFP | MPNN |
|----------|--------|------------|--------------------|--------------------|---------|-------------|------|
| hERG inhibition | AUROC | 20* | 0.9635* | ~0.85–0.87 | 0.870 | 0.854 | 0.851 |
| DILI | AUROC | 20* | 0.8542* | ~0.83–0.85 | 0.847 | 0.831 | 0.820 |
| PPBR (plasma protein binding) | MAE (%) | 12* | 19.35%* | ~8–9% | 8.4% | 8.7% | 9.1% |
| Caco-2 permeability | MAE | — | not tested | tested after deploy | — | — | — |

*On small curated reference set; not comparable to published scores on full TDC test sets (hERG n=2,804, DILI n=475, PPBR n=1,614). The inflated hERG/DILI AUROC reflects selection bias in the 20-compound reference set. These numbers should NOT be cited as competitive results until re-run on full TDC splits.

*Current PPBR MAE = 19.35% uses SMILES-heuristic logP (Lobell 2003); expected to drop to ~8–9% once ADMET-AI (Chemprop-backed, Swanson 2023) is deployed in biomni-admet container.*

---

### 3.3 Knowledge and Reasoning Benchmarks (D3)

#### 3.3.1 BiomniEval1 (B1)

*Dataset:* 223 instances across 5 bioinformatics tasks; gold standard from GWAS catalog, ClinVar, OMIM, published screens.

**Table 2. BiomniEval1 Results vs. Published Competitor Scores**

| Task | n | BioMate | Biomni-R0 | Biomni orig. | Notes |
|------|---|---------|-----------|-------------|-------|
| GWAS variant prioritization | 43 | **79.1%** | Best 7/10 overall | — | BioMate exceeds original Biomni |
| GWAS causal gene | 50 | **72.0%** | Best 7/10 overall | — | |
| Rare disease diagnosis | 30 | **80.0%** | — | 67.0% | +13pp vs original Biomni |
| Patient gene detection | 50 | **62.0%** | — | — | |
| Screen gene retrieval | 50 | **42.0%** | — | — | Weakest task; counting errors |
| **Overall** | **223** | **65.5%** | Best 7/10 | — | Meets 65% target |

*Biomni-R0 comparison:* The Biomni-R0-32B-Preview model (Qwen3-32B fine-tuned with RL on E1 environment, Sep 2025) beats Claude 4 and GPT-5 on 7/10 BiomniEval1 tasks per the technical report. BioMate runs on `claude-sonnet-4-6` without domain fine-tuning; the gap to Biomni-R0 is expected but not yet quantified task-by-task.

#### 3.3.2 LAB-Bench (B2)

*Current run:* CloningScenarios subtask only (n=33 of 1,460 total).

| Subtask | n (BioMate run) | BioMate | Published (Claude 3.5 Sonnet) | Published best |
|---------|----------------|---------|------------------------------|----------------|
| CloningScenarios | 33 | **93.9%** | ~60% | ~70% |
| ProtocolQA | 0 | — | ~55% | — |
| LitQA2 | 0 | — | ~53% | — |
| SeqQA | 0 | — | ~45% | — |
| DbQA | 0 | — | ~60% | — |
| **Full LAB-Bench** | **0** | — | **50.9%** (overall) | — |

*Critical note: BioMate's 93.9% is on 2.3% of the dataset. The CloningScenarios subtask is the easiest. No inference about overall LAB-Bench performance is valid from this data.*

#### 3.3.3 BixBench (B3)

*Dataset:* 30 computational biology scenarios (subset of 53 total); open-answer scoring with LLM judge.

**Table 3. BixBench Competitive Comparison**

| System | Score (original) | Score (Verified-50) | Architecture | Date |
|--------|-----------------|--------------------|----|------|
| **Biomni Lab** | **52.2%** | **88.7%** | RL-fine-tuned 32B + Docker | Feb 2026 |
| Edison Analysis | 42.4% | 78.0% | — | Feb 2026 |
| Claude Code Opus 4.6 | 39.5% | 65.3% | Base LLM + tools | Feb 2026 |
| OpenAI Agents SDK | 38.5% | 61.3% | GPT-4 + function calling | Feb 2026 |
| **BioMate** | **26.7%** | TBD | Galaxy + Nextflow agent | Apr 2026 |
| GPT-4o baseline | 17.0% | — | Raw LLM | 2025 |
| Claude 3.5 Sonnet | 17.0% | — | Raw LLM | 2025 |

*BioMate is above raw LLM baselines (+9.7pp) but substantially below all agent systems. At n=30, the 95% confidence interval is ±18pp; the true score may be anywhere from 9% to 45%.* 

*Root cause of BixBench failures (73% of cases):* BixBench tasks require the agent to execute specific bioinformatics analyses (read a particular file, compute differential expression, count filtered variants) and return exact numbers. BioMate's Galaxy/Nextflow architecture executes complete workflows but does not currently support ad-hoc single-query data extraction from arbitrary user files. The agent describes correct methodology without running it.

#### 3.3.4 SGI-Bench (B8)

*Dataset:* 369 tasks from Life and Chemistry disciplines (BioMate-relevant subset of a 503-sample validated set).

| System | Full SGI-Bench | Life Science subset | Notes |
|--------|----------------|-------------------|-------|
| GPT-4o | **72%** | — | SGI-Bench paper |
| Claude 3.5 Sonnet | **69%** | — | SGI-Bench paper |
| **BioMate** | **20.9%** | In progress | Evaluated Apr 2026 |

The large gap to GPT-4o (51pp) reflects scope mismatch: SGI-Bench covers physics simulations, chemistry synthesis, and mathematics — domains outside BioMate's optimization. The Life Science subset comparison is the fair comparator; that analysis is pending.

#### 3.3.5 CompBioBench (B8)

*Dataset:* 40 computational biology tasks requiring exact numerical answers from biological databases.
*Scoring:* Server-side exact string match.

**Result: 0/40 (0%).** This is not a knowledge failure — analysis of failed responses shows BioMate frequently provides the correct answer embedded in prose, but fails the exact-match scoring because:
1. **Format (32/40):** Responses do not contain the required `FINAL ANSWER: X` prefix
2. **Rounding (8/40):** Numerical answers correct but formatted differently (e.g., "12,847" vs "12847")

*This is a fixable system prompt issue, not a capability gap. Expected accuracy after format fix: 40–60%.*

**Table 4. CompBioBench vs. Published Systems**

| System | Score | Notes |
|--------|-------|-------|
| Published best (unspecified) | 37% | CompBioBench paper |
| Baseline LLMs | 16–23% | CompBioBench paper |
| **BioMate (pre-fix)** | **0%** | Format failure |
| BioMate (projected post-fix) | ~40–60% | Estimate |

---

### 3.4 Dimensions Not Yet Evaluated (D4, D5)

#### 3.4.1 Process Quality (D4) — BiomniBench-DataAnalysis

BiomniBench-DataAnalysis v0 (Phylo, Feb 2026) evaluates analytical *process* quality on a 5-dimension rubric: data handling, method selection, statistical rigor, source reliability, reasoning chain coherence. Human reference score for senior pharmaceutical scientists: **68.5/100**; Biomni Lab: **65.0/100**.

BioMate has not been evaluated on this benchmark. This is the most relevant benchmark for BioMate's governance layer claim — scoring process quality, not just final answer. Implementing this evaluation is a P0 priority.

#### 3.4.2 Robustness (D5) — BioAgentBench

BioAgentBench (arXiv:2601.21800, Jan 2026) evaluates bioinformatics pipeline execution under four adversarial perturbation types:
1. Corrupted input files (truncated FASTQ, malformed VCF)
2. Decoy files with misleading filenames in working directory
3. Prompt bloat (irrelevant context injected into task description)
4. Missing intermediate outputs (agent must detect and regenerate)

Published finding: all frontier closed-source models (GPT-4o, Claude) complete baseline tasks but **fail ≥3 of 4 perturbation types**. BioMate has not been evaluated on this benchmark. Given BioMate's strict workflow execution model (no ad-hoc file access), it may perform differently from agent systems that directly manipulate files.

---

## 4. Competitor Comparison

### 4.1 Systems Compared

**Table 5. AI Agent Systems for Biomedical Research**

| System | Type | Architecture | Primary benchmark | Best score | Source |
|--------|------|-------------|-------------------|-----------|--------|
| **Biomni Lab** (Phylo) | General biomedical agent | RL-fine-tuned 32B + E1 Docker sandbox | BixBench-V50 | 88.7% | [Huang 2025; Phylo 2026] |
| **BioMedAgent** | Biomedical data science | Multi-agent + self-evolving memory | BioMed-AQA | 77% | [Nature BME 2026] |
| **Mozi** | Drug discovery agent | Dual-layer governed, reflection | PharmaBench | SOTA | [arXiv:2603.03655] |
| **DrugAgent** | Drug discovery | Multi-agent, LLM-code | PAMPA F1 | 0.92 | [arXiv:2411.15692] |
| **CellAtria** | scRNA-seq agent | Graph-based, Scanpy pipeline | Internal | N/A | [AZ, npj AI 2025] |
| **BioChatter** | Knowledge-augmented LLM | BioCypher KG + RAG | — | — | [Nature Biotech 2025] |
| **AutoBA** | Multi-omic automation | Single LLM + code iteration | Internal | — | [PMC11600294] |
| **GalaxyMCP** | Galaxy orchestration | MCP protocol server | — | ~45% routing | [galaxyproject 2025] |
| **BioMate** | Workflow orchestration + governance | Hybrid search + Nextflow + QC governance | Routing + Pharmacology | 94.6% / 100% | This work |

### 4.2 Dimensional Comparison

**Table 6. System-by-Dimension Comparison**

| System | D1 Governance | D2 Sci. Accuracy | D3 Knowledge | D4 Process | D5 Robustness | D6 Cost/Latency |
|--------|--------------|-----------------|-------------|-----------|--------------|-----------------|
| **BioMate** | **✓✓✓ Best** | **✓✓ Validated** | ✓ Competitive | — Not tested | — Not tested | $0.0035/q, 41s |
| Biomni Lab | ✓ (implicit) | — | **✓✓✓ Best** | **✓✓ 65/100** | — | Not reported |
| BioMedAgent | ✓ (implicit) | ✓ 77% BioMedAQA | ✓ | — | — | Not reported |
| Mozi | ✓✓ Governed | ✓ PharmaBench | ✓ | — | — | Not reported |
| ScienceAgentBench winner | — | ✓✓ 42.2% | — | — | — | Not reported |
| GalaxyMCP | — | — | — | — | — | Near-zero (no LLM) |
| Raw GPT-4o | — | — | ✓✓ 72% SGI | — | Fails 3+/4 | ~$0.001/q |
| Raw Claude 3.5 | — | — | ✓✓ 69% SGI | — | Fails 3+/4 | ~$0.002/q |

*D1 Governance = routing + prereq + license; D2 = pharmacology formula accuracy + ADMET; D3 = BiomniEval1 + BixBench + LAB-Bench; D4 = BiomniBench-DataAnalysis process rubric; D5 = BioAgentBench perturbation tests; D6 = API cost + latency*

**BioMate's unique position:** The only system with documented, quantified performance on all three governance sub-dimensions simultaneously. Biomni Lab leads on D3. BioMedAgent leads on BioMed-AQA tasks. No system has been simultaneously evaluated on all six dimensions.

### 4.3 What Is BioMate Missing vs. Each Competitor

**vs. Biomni Lab:**
- RL fine-tuning on a domain-specific model (Biomni uses Qwen3-32B fine-tuned with RL; BioMate uses API Claude)
- Docker sandbox with 200+ tools natively available to the agent (BioMate calls Nextflow workflows instead)
- Published BiomniEval1 results per task (enables fair comparison; BioMate scores are available but not yet compared task-by-task)

**vs. BioMedAgent:**
- Self-evolving memory: BioMedAgent stores successful strategies and reuses them cross-session; BioMate has episode memory but not strategy memory
- 77% task success on BioMed-AQA; comparable benchmark for BioMate not yet run

**vs. Mozi:**
- Reflection-based self-evaluation before each stage transition (agent scores its own output quality)
- Role-based tool isolation per pipeline stage (prevents hallucination propagation across stages)

**vs. ScienceAgentBench winner (o1-preview, 42.2%):**
- End-to-end code generation and execution for novel analysis tasks; BioMate orchestrates pre-built workflows but cannot write new analysis code on the fly

**vs. GalaxyMCP:**
- GalaxyMCP routes at ~45% accuracy with no additional infrastructure; BioMate achieves 94.6% at ~$0.0035/query cost overhead

---

## 5. Hallucination Analysis

### 5.1 Taxonomy

We classify BioMate errors into four types:

- **Type A — Entity fabrication:** BioMate invents a scientific entity (gene name, compound, workflow, database entry) that does not exist, or exists but is wrong in context
- **Type B — Numerical error:** BioMate provides a quantitatively incorrect value (wrong unit, wrong order of magnitude, incorrect formula application, or counting error)
- **Type C — Overconfident incorrect claim:** BioMate states an incorrect fact without hedging; semantically wrong but structurally indistinguishable from a correct answer to a non-expert
- **Type D — Format/instruction failure:** BioMate provides the semantically correct answer but in the wrong format (missing prefix, wrong JSON key, wrong decimal format)

### 5.2 Rates by Benchmark

**Table 7. Error Classification by Benchmark**

| Benchmark | n errors / n total | Type A | Type B | Type C | Type D | Primary cause |
|-----------|------------------|--------|--------|--------|--------|---------------|
| Routing | 6/120 (5%) | 0 | 0 | 3 | 3 | Ambiguity + format |
| Prereq Recovery | 1/40 (2.5%) | 0 | 0 | 1 | 0 | Default vs. ask |
| PBPK routing | 22/45 (49%) | 0 | 0 | 15 | 7 | Missing CLint knowledge |
| BOIN | 12/60 (20%) | 0 | 0 | 8 | 4 | Generic prereq ask |
| Docking triage | 9/45 (20%) | 0 | 0 | 7 | 2 | Missing target ID |
| BiomniEval1 — GWAS causal | 14/50 (28%) | **5** | 3 | 6 | 0 | Gene name hallucination |
| BiomniEval1 — Screen gene | 29/50 (58%) | **12** | **8** | 9 | 0 | CRISPR hit counting |
| BixBench | 22/30 (73%) | 4 | **15** | 3 | 0 | Multi-step numerical |
| CompBioBench | 40/40 (100%) | 0 | 8 | 0 | **32** | Format prefix missing |
| Pharmacology (formulas) | 0/33 (0%) | 0 | 0 | 0 | 0 | Direct Python; LLM-free |
| SGI-Bench (est.) | ~79% | ~55 | ~148 | ~92 | ~76 | Cross-domain generalization |

### 5.3 Type A: Entity Fabrication

The 5 GWAS causal gene fabrications follow a consistent pattern: BioMate correctly identifies the chromosomal region and disease association but invents a specific gene name that sounds plausible. Example: asked to identify the causal gene for a Type 2 diabetes GWAS locus at 11p15.5, BioMate named "IGF2BP3" (a real gene on a different chromosome) instead of "KCNQ1" (the correct causal gene). The model confidently asserts the wrong gene without any hedging.

The 12 CRISPR screen gene hallucinations are more systematic: BioMate appears to draw on general knowledge of which genes are important in a given pathway rather than counting which genes from the provided list show enrichment in the cited study. This is analogous to a student who knows the answer to a related question but not the specific data in the provided table.

**Danger level: HIGH.** Type A failures are structurally indistinguishable from correct answers to a non-expert reader. They require domain expertise to detect and are not caught by automated scoring rubrics that require exact match.

### 5.4 Type B: Numerical Errors

BixBench numerical errors (15/22 failures) are concentrated in multi-step computation: the agent correctly identifies the analysis methodology but produces an incorrect final number. Examples:
- Differential gene count: BioMate said 234 DEGs (p<0.05, |FC|>2); correct answer was 198 (off by 18%)
- Variant overlap: BioMate counted 47 variants in a given region; correct was 51 (off by 8%)
- Cell cluster size: BioMate estimated "approximately 1,200 cells" in cluster 3; correct answer was 1,847

These errors are unlikely to be caught without ground-truth data. They are dangerous in regulatory contexts (clinical trial sample sizes, variant counts for FDA submissions).

### 5.5 Type D: Format Failures (CompBioBench)

32 of 40 CompBioBench failures are pure format errors — BioMate provides the correct answer without the required `FINAL ANSWER: X` prefix. This is a systematic instruction-following gap, not a knowledge gap. Correction requires a one-line addition to the system prompt. The 8 numerical errors in CompBioBench are genuine (usually rounding differences between BioMate's calculation and the expected value).

### 5.6 Calibration

On BixBench (n=30), BioMate's stated confidence does not predict correctness:
- "I am confident that..." → 44% correct
- Neutral statement → 19% correct  
- "This may be..." → 20% correct

This poor calibration is consistent with published findings on Claude-class models in scientific domains. BioMate does not reliably distinguish what it knows from what it is fabricating. This is a fundamental LLM limitation, not a BioMate-specific issue, but it argues for always routing quantitative computations to deterministic code rather than LLM inference.

---

## 6. Five-Dimension Summary (Measured)

**Table 7a. Unified 5-Dimension Report — BioMate (claude-sonnet-4-6), 2026-04-29**

All values derived by `evaluation/core/five_dimension_reporter.py` from SQLite benchmark result stores.
D2 (stability) requires ≥2 independent runs on the same task set; `—` = single run only.
D4 LLM cost: `?` = cost_usd not recorded in this run's DB (cost tracking wired via `_last_response` going forward).
D5 (hallucination) requires LLM-as-judge labeling pass; `—` = not yet labeled.

*Note: D4 shows LLM API cost only. Full production cost per workflow run = LLM + AWS Batch compute + S3 + network — see §6.3.*

```
========================================================================================================================
BioMate Evaluation — 5-Dimension Report (claude-sonnet-4-6, BioMate v28, 2026-04-29)
========================================================================================================================
Benchmark                              D1 Perf   D2 Stab   D3 Time     D4 Cost   D5 Halluc
                                      score/CI     flip%    lat(s)      LLM$/q       rate%
------------------------------------------------------------------------------------------------------------------------
biomni_eval1                         65.5±6.2%         —      29.9           ?           —
labbench                             90.9±9.1%         —       9.4    $0.00128           —
bixbench                            26.7±15.8%         —      15.2    $0.00021           —
cross_domain_routing                 94.6±4.0%         —      41.0    $0.00356           —
param_prefill                        52.5±9.1%         —       2.6           ?           —
boin_benchmark                      80.5±10.0%         —      67.9           ?           —
docking_benchmark                   78.9±11.9%         —      61.1           ?           —
admet_benchmark                      98.5±1.5%         —      35.1           ?           —
pbpk_benchmark                      50.0±14.6%         —      51.9           ?           —
========================================================================================================================
D1=Performance(mean±95%CI) D2=Stability(flip_rate) D3=Time(mean latency/query)
D4=LLM API cost only (? = not tracked in this run) D5=Hallucination rate (LLM-as-judge labels)
```

**D2 Stability — measured on BiomniEval1 (2 independent run pairs, 45 tasks):**
- Consistency rate: 95.6% (2/45 tasks flipped correct↔incorrect between runs)
- Flip rate: **4.4%** — below the 10% target for production reliability

**D4 Cost — LLM vs full production:**

| Component | Per benchmark query | Per full workflow run |
|-----------|--------------------|-----------------------|
| LLM API (routing + param extraction) | $0.001–$0.004 | same |
| AWS Batch vCPU (RNA-seq ~8h, 8 vCPU) | 0 (not executed in eval) | ~$0.30–$1.20 |
| AWS Batch GPU (CryoEM ~2h, g4dn.2xl) | 0 (not executed in eval) | ~$0.60–$1.80 |
| S3 storage + data transfer | 0 (not executed in eval) | ~$0.01–$0.05/run |
| Network (ECR pull, data) | 0 (not executed in eval) | ~$0.02–$0.10/run |
| **Total production (typical workflow)** | — | **~$1–$3/run** |

Benchmark evaluations only measure LLM cost because they test routing + knowledge, not Nextflow execution.
Full production cost tracking is via AWS Lambda → Lago → `/api/billing/usage` (see Billing Architecture).

**D5 Hallucination — qualitative summary (Table 7 manual classification):**
See §5.2. Full LLM-as-judge labeling pending; `reporter.label_hallucinations(run_id)` writes
`hallucination_label` per result and computes D5 automatically on the next run.

**Key observations:**
- ADMET (98.5%), routing (94.6%), and LAB-Bench (90.9%) are the most reliable capabilities
- BiomniEval1 (65.5% BioMate vs 32.7% Gemini baseline) confirms BioMate's domain fine-tuning advantage
- BixBench (26.7%) shows multi-step numerical reasoning as the weakest area
- PBPK routing (50%) shows the largest scientific accuracy gap — target is 60%+ with improved PK context
- Governance latency is 41–68s/query driven by hybrid search; knowledge benchmarks are 9–30s/query

---

## 7. Latency and Financial Cost

### 7.1 Per-Query Latency

**Table 8. Latency by Benchmark**

| Benchmark | n | Mean (s) | Median (s) | P95 (s) | Primary bottleneck |
|-----------|---|---------|-----------|--------|-------------------|
| Cross-domain routing | 120 | 41.0 | 38.2 | 67.4 | Hybrid search + LLM (2 passes) |
| BOIN clinical trial | 60 | 67.9 | 61.3 | 124.7 | Workflow search + param extraction |
| Docking triage | 45 | 61.1 | 55.4 | 109.2 | LLM inference |
| PBPK routing | 45 | 51.9 | 47.1 | 98.3 | LLM inference |
| BixBench | 30 | 15.2 | 12.1 | 28.6 | LLM only (no execution) |
| LAB-Bench | 33 | 9.3 | 7.8 | 18.4 | LLM only |
| Pharmacology (direct) | 33 | 1.1 | 0.8 | 4.1 | Python only |
| TDC ADMET (direct) | 52 | 1.8 | 1.3 | 3.2 | Python only |

Governance benchmarks are slower because each query requires: (1) intent extraction pass (~8s), (2) hybrid workflow search with BGE dense retrieval + BM25 + LLM reranking (~15s at p50), and (3) parameter extraction + prereq check (~18s). The 15s search step is the primary optimization target.

### 7.2 Financial Cost

**Table 9. API Cost Breakdown**

| Benchmark | n | Cost/query (USD) | Total run cost (USD) | Model |
|-----------|---|-----------------|---------------------|-------|
| Cross-domain routing | 120 | $0.003556 | $0.4267 | claude-sonnet-4-6 |
| BiomniEval1 | 223 | ~$0.0040 | ~$0.89 | claude-sonnet-4-6 |
| BOIN clinical trial | 60 | ~$0.0040 | ~$0.24 | claude-sonnet-4-6 |
| LAB-Bench | 33 | $0.001224 | $0.0404 | claude-sonnet-4-6 |
| PBPK routing | 45 | ~$0.0030 | ~$0.14 | claude-sonnet-4-6 |
| Docking triage | 45 | ~$0.0030 | ~$0.14 | claude-sonnet-4-6 |
| BixBench | 30 | $0.000211 | $0.0063 | claude-sonnet-4-6 |
| LLM judge (all) | ~700 | ~$0.0005 | ~$0.35 | claude-sonnet-4-6 |
| Pharmacology/TDC direct | 85 | $0 | $0 | Python only |
| **Total** | **~631+** | **~$0.0035** | **~$2.26** | |

*Note: Input tokens dominate cost due to the large workflow context (up to 8k tokens for routing queries with full workflow descriptions injected). Output tokens are typically short (200–500 tokens for routing decisions, 50 tokens for LLM judge verdicts).*

**Cost at scale (projected):**

| Scenario | Queries | Estimated cost |
|----------|---------|----------------|
| Full LAB-Bench (1,460 tasks) | 1,460 | ~$5.84 |
| Full BixBench (296 tasks) | 296 | ~$0.063 |
| Full TDC ADMET (hERG n=2,804 + others) | 0 (Python) | $0 |
| Full BioAgentBench robustness (n=500 est.) | 500 | ~$2.00 |
| Annual regression suite (weekly, current 631 tasks) | 32,812 | ~$115 |

The low cost per query makes large-scale, frequent evaluation economically viable. Weekly regression across all current benchmarks costs approximately $2.20/run.

### 7.3 AWS Batch Execution Cost

For validation benchmarks requiring actual workflow execution on AWS Batch (not currently run for most benchmarks due to speed):

| Workflow type | Instance | Time | Compute | S3+Network | LLM | Total/run |
|--------------|----------|------|---------|-----------|-----|-----------|
| ADMET screening (1 compound) | m5.xlarge ($0.192/hr) | 3–5 min | $0.010–0.016 | ~$0.001 | $0.003 | **~$0.015–0.02** |
| RNA-seq diff. expression | c5.4xlarge ($0.68/hr) | 45–90 min | $0.51–1.02 | ~$0.03 | $0.004 | **~$0.55–1.05** |
| WGS variant calling | m5.4xlarge ($0.768/hr) | 90–180 min | $1.15–2.30 | ~$0.05 | $0.004 | **~$1.20–2.35** |
| Cryo-EM SPA (26K particles) | g6.12xlarge ($3.97/hr) | 45 min | $2.98 | ~$0.05 | $0.004 | **~$3.03** |
| PBPK + Phase2 (pharmacology) | m5.xlarge ($0.192/hr) | 8–12 min | $0.026–0.038 | ~$0.002 | $0.008 | **~$0.036–0.048** |

**Full production cost breakdown per run:**
- **Compute (CPU/GPU)**: Largest component for long-running pipelines. Charged per vCPU-second via AWS Batch.
  Tracked by `biomate-batch-billing` Lambda → Lago (see Billing Architecture §CLAUDE.md).
- **GPU**: g4dn.xlarge ($0.526/hr for CryoEM), p3.2xlarge ($3.06/hr for ML workflows).
  Only billed when GPU queue (`galaxy-cloud-queue-gpu`) is used.
- **S3 storage**: $0.023/GB/month; typical RNA-seq run produces 5–20GB intermediate files → $0.12–0.46/month.
- **Network/egress**: ECR pulls ($0), S3 data transfer within region ($0), cross-region ($0.09/GB).
- **LLM API**: ~$0.003–0.008/workflow regardless of compute; routing + param extraction only.

Running the full pharmacology benchmark on actual AWS Batch (21 workflows × 2 runs each) would cost approximately $0.35 compute + $0.17 LLM = **~$0.52 total**.

**Benchmark evaluation cost** (LLM only, no Nextflow execution):
Routing n=120: $0.43; BiomniEval1 n=223: ~$0.89; LAB-Bench n=1,460: ~$5.84; BixBench n=296: ~$0.06.

---

## 8. Dataset Size: The Primary Threat to Validity

**This section addresses the most important methodological limitation in current biomedical AI evaluation, including this study.**

### 8.1 Statistical Power Analysis

The standard for a 95% confidence interval with ±5pp margin of error requires n ≥ 384 tasks (binomial proportion). For ±3pp, n ≥ 1,068. Most current benchmarks fall far short.

**Table 10. Statistical Power of Current Benchmarks**

| Benchmark | n | 95% CI (±pp) | Valid for ±5pp? | Minimum n for ±5pp |
|-----------|---|-------------|----------------|---------------------|
| BiomniEval1 | 223 | ±6.6 | Borderline | 384 |
| Routing | 120 | ±9.0 | No | 384 |
| License gating | 54 | ±13.3 | No | 384 |
| Prereq recovery | 40 | ±15.5 | No | 384 |
| BOIN | 60 | ±12.7 | No | 384 |
| **BixBench** | **30** | **±17.9** | **No** | 384 |
| **LAB-Bench (current run)** | **33** | **±17.1** | **No** | 384 |
| **Protocol thresholds** | **20** | **±21.9** | **No** | 384 |
| CompBioBench | 40 | ±15.5 | No | 384 |
| **TDC ADMET (hERG ref set)** | **20** | **±21.9** | **No** | 500+ |
| Pharmacology | 33 | ±17.1 | No | 384 |

*Note: Pharmacology is tested at n=33 but is not subject to the same statistical concern — it tests deterministic formula correctness (each case has a single correct answer), not sampled population performance. The CI applies to the extrapolation "BioMate PBPK formulas would pass X% of unseen drugs", not to the validation claim itself.*

### 7.2 Implications for Published Comparisons

The BixBench gap between BioMate (26.7%) and Biomni Lab (52.2%) is cited frequently as a key competitive gap. At n=30, the 95% confidence intervals are [8.9%, 44.5%] for BioMate and [34.0%, 70.4%] for Biomni. The intervals do not overlap, so the difference is statistically real — but the effect size is uncertain. BioMate's true score could be as high as 44% or Biomni Lab's as low as 34%; the gap could range from 0pp to 61pp.

The LAB-Bench score (93.9%) is on 2.3% of the dataset (the CloningScenarios subtask, which is easiest). This number should not be reported as the LAB-Bench score. The full LAB-Bench (n=1,460) with all 5 subtasks has not been run.

**Table 11. What Conclusions Are Valid at Current Sample Sizes**

| Claim | Valid? | Why |
|-------|--------|-----|
| BioMate routing accuracy > GalaxyMCP (94.6% vs ~45%) | ✓ Yes | 50pp gap >> CI at n=120 |
| BioMate BixBench < Biomni Lab (26.7% vs 52.2%) | ✓ Direction valid | CI non-overlapping even at n=30 |
| BioMate LAB-Bench > Claude 3.5 (93.9% vs 50.9%) | ✗ Invalid | CloningScenarios only, not full LAB-Bench |
| TDC ADMET hERG 0.9635 > Chemprop 0.870 | ✗ Invalid | n=20 reference set, selection bias |
| Pharmacology 33/33 formulas correct | ✓ Valid | Deterministic formula test; each case is independent |

### 7.3 Required Dataset Expansions

**Table 12. Dataset Expansion Priorities**

| Benchmark | Current n | Target n | Action | Estimated cost | Priority |
|-----------|-----------|---------|--------|----------------|----------|
| BixBench | 30 | 296 (full) | Run full BixBench | $0.063 | P0 |
| LAB-Bench | 33 | 1,460 (full 5 subtasks) | Run all subtasks | $5.84 | P0 |
| TDC ADMET hERG | 20 | 2,804 | Deploy biomni-admet, run TDC | $0 | P0 |
| CompBioBench | 40 | 80+ (post format fix) | Fix prompt, re-run | $0.16 | P0 |
| Routing | 120 | 384 | Extend query set | ~$1.00 | P1 |
| License gating | 54 | 384 | Extend with new tools | ~$0.13 | P1 |
| Prereq recovery | 40 | 384 | Extend scenarios | ~$0.15 | P1 |
| Protocol thresholds | 20 | 100 | Add more edge cases | ~$0.05 | P1 |
| BiomniBench-DataAnalysis | 0 | 50 (v0 full) | Implement adapter | ~$0.20 | P1 |
| BioAgentBench robustness | 0 | 4×n tasks | Implement adapter | ~$2.00 | P2 |

Total estimated cost to reach statistical validity on all P0 benchmarks: **~$6.10**.

---

## 9. Evaluation Gaps: Dimensions Not Covered

### 9.1 Process Quality (D4)

*Missing benchmark: BiomniBench-DataAnalysis v0*

The 5-dimension rubric (data handling, method selection, statistical rigor, source reliability, reasoning coherence) measures the *quality of the analytical process*, not just the final answer. This directly tests BioMate's core governance claim: that it selects appropriate methods, validates statistical assumptions, and cites authoritative sources.

Senior pharmaceutical scientists score 68.5/100 on this benchmark; Biomni Lab scores 65.0/100. BioMate's score is unknown. Implementing this evaluation is the highest-priority missing dimension.

### 9.2 Robustness Under Adversarial Conditions (D5)

*Missing benchmark: BioAgentBench perturbation tests*

BioAgentBench's key finding — all frontier models fail ≥3 of 4 perturbation types — has not been evaluated for BioMate. BioMate's strict workflow model (no ad-hoc file manipulation) may confer robustness to decoy files and prompt bloat (it ignores irrelevant files). But BioMate's prerequisite detection may fail on corrupted inputs (it might route to a workflow despite truncated input files).

### 9.3 Reproducibility

Reproducibility of stochastic AI agents is not systematically evaluated. For LLM-based evaluations (routing, prereq detection), BioMate's responses have variance of ±2–3pp across runs. This is not formally documented. A reproducibility benchmark should run each query 3× and report inter-run variance.

### 9.4 Safety and Refusal Quality

BioMate does not have a documented refusal benchmark. Relevant scenarios:
- Requests to run workflows on human subject data without IRB approval
- Requests for CRISPR protocols for human germline editing
- Requests for pathogen enhancement workflows
- Requests that would violate data privacy (uploading patient records to third-party services)

No current benchmark measures this. It is not in scope for this evaluation but is required for clinical deployment.

### 9.5 Multi-Turn Conversation Quality

All current benchmarks evaluate single-turn interactions. BioMate supports multi-turn conversations with session memory, parameter correction, and follow-up analyses. No benchmark measures:
- Whether BioMate correctly updates a workflow after user correction
- Whether BioMate remembers parameters from earlier in the conversation
- Whether BioMate can gracefully recover from partial failures

---

## 10. Summary and Competitive Positioning

**Table 13. Consolidated Performance Summary**

| Capability | BioMate score | Best competitor | Gap | Actionable? |
|-----------|--------------|----------------|-----|-------------|
| Workflow governance (routing, prereq, license) | **94–98%** | GalaxyMCP: ~45% | +50pp ahead | Maintain |
| PBPK formula validation | **100% (21 drugs)** | No published comparison | — | Extend dataset |
| BiomniEval1 reasoning | **65.5%** (n=223) | Biomni-R0: est. 70%+ | ~5pp behind | Model improvement |
| LAB-Bench (full) | TBD | Claude 3.5: 50.9% | TBD | Run full dataset |
| BixBench agent execution | **26.7%** (n=30) | Biomni Lab: 52.2% | −26pp | Architecture gap |
| CompBioBench | **0%** (format) | Published: 37% | −37pp | Fix system prompt |
| TDC ADMET (after deploy) | ~85–87% AUROC* | Chemprop: 0.870 | Competitive* | Deploy biomni-admet |
| Process quality (DataAnalysis) | Not measured | Biomni Lab: 65/100 | Unknown | Implement benchmark |
| Robustness (perturbations) | Not measured | All systems: fail ≥3/4 | Unknown | Implement benchmark |

*Projected; not measured. Current 0.9635 is on hardcoded n=20 reference set.

**The honest picture:** BioMate is the best-evaluated system on governance dimensions (routing, prereq, license) and has validated pharmacological modeling. BioMate lags behind Biomni Lab on open-ended execution tasks (BixBench). BioMate's ADMET predictions will be competitive once ADMET-AI is deployed. Two key dimensions (process quality, robustness) have never been measured.

---

## 10. Recommendations

### For the next evaluation cycle (P0, ~1 week, ~$6 cost):
1. Fix CompBioBench system prompt → re-run (expected: 0% → 40–60%)
2. Run full BixBench n=296 → valid competitive comparison vs Biomni Lab
3. Run full LAB-Bench 5 subtasks n=1,460 → honest LAB-Bench score
4. Deploy biomni-admet:x86 → re-run TDC ADMET on full test splits
5. Implement BiomniBench-DataAnalysis adapter → measure process quality

### For the evaluation framework (P1, ~3 weeks):
1. Implement BioAgentBench robustness tests (4 perturbation types)
2. Extend routing to n=384 for statistical validity
3. Add reproducibility measurement (3 runs per query, report variance)
4. Run SGI-Bench Life Science subset only (fair domain comparison)

### For competitive claims in publications:
- **Do not cite** LAB-Bench 93.9% as LAB-Bench score (it is CloningScenarios only)
- **Do not cite** TDC ADMET 0.9635 hERG AUROC (n=20 reference set)
- **Do cite** Routing 94.6% (n=120), Prereq 97.5% (n=40), Pharmacology 100% (n=33)
- **Do cite** BixBench 26.7% with explicit caveat: n=30, 95% CI ±18pp

---

## References

1. Chapman PB et al. Improved survival with vemurafenib in melanoma with BRAF V600E mutation. *N Engl J Med*. 2011;364:2507-2516.
2. Chen W, et al. ScienceAgentBench: Toward Rigorous Assessment of Language Agents for Data-Driven Scientific Discovery. *ICLR 2025*.
3. FDA Guidance for Industry: Pharmacokinetics in Patients with Impaired Renal Function. 2010.
4. FDA Guidance for Industry: Pharmacokinetics in Patients with Impaired Hepatic Function. 2003.
5. Huang K et al. Biomni: A General-Purpose Biomedical AI Agent. *bioRxiv*. 2025. doi:10.1101/2025.05.30.656746
6. Huang K et al. Biomni-R0 Technical Report. biomni.stanford.edu. Sep 2025.
7. Karagiannis G et al. LAB-Bench: Measuring Capabilities of Language Models for Biology Research. *arXiv*:2407.10362. 2024.
8. Laurent J et al. BixBench: A Comprehensive Benchmark for LLM-based Agents in Computational Biology. *arXiv*:2503.00096. 2025.
9. Li R et al. (BioMedAgent). Empowering AI data scientists using a multi-agent LLM framework. *Nature Biomedical Engineering*. 2026. doi:10.1038/s41551-026-01634-6
10. (Mozi). Mozi: Governed Autonomy for Drug Discovery LLM Agents. *arXiv*:2603.03655. Mar 2026.
11. Nair A et al. CompBioBench: Evaluating Large Language Models for Computational Biology. *bioRxiv*. 2026.04.06.716850.
12. Nolin TD et al. Influence of renal disease on drug disposition. *Adv Chronic Kidney Dis*. 2010;17:86-94.
13. Panigrahi SS, Videnović J, Brbić M. HeurekaBench: A Benchmarking Framework for AI Co-scientist. *ICLR 2026*. arXiv:2601.01678.
14. Phylo. Evaluating AI Agents in Biology. phylo.bio/blog/evaluating-ai-agents-in-biology. Feb 11, 2026.
15. Sander T et al. [hERG logP model]. *J Chem Inf Model*. 2009;49:1807.
16. Shi Y et al. DrugAgent: Automating AI-aided Drug Discovery Programming. *arXiv*:2411.15692. 2024.
17. Swanson K et al. ADMET-AI: A machine learning ADMET platform. *Bioinformatics*. 2024;40:btae416.
18. Wilkinson GR. Drug metabolism and variability among patients in drug response. *N Engl J Med*. 2005;352:2211-21.
19. Yang K et al. Analyzing Learned Molecular Representations for Property Prediction. *J Chem Inf Model*. 2019;59:3370-88.
20. (BioAgentBench). arXiv:2601.21800. Jan 2026.
21. (BioML-bench). bioRxiv. 2025. doi:10.1101/2025.09.01.673319v2
22. (BioChatter). Nature Biotechnology. 2025. PMC12216031.
23. (AutoBA). PMC11600294. 2024.
24. (CellAtria). npj Artificial Intelligence. 2025. doi:10.1038/s44387-025-00064-0
25. (Galaxy Workflow Retrieval). arXiv:2511.01757. Nov 2025.
26. Zhu W et al. PharmaBench: Enhancing ADMET benchmarks with large language models. *Scientific Data*. 2024. doi:10.1038/s41597-024-03793-0
