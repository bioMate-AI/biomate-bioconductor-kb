# Competitor & Benchmark Landscape — BioMate Evaluation Reference
**Date:** 2026-04-01  
**Purpose:** Authoritative reference for paper claims, evaluation design, and competitive positioning. All scores cited with source.

---

## Part 1 — Benchmark Registry

Each benchmark is described with enough detail to reproduce the evaluation and integrate it into BioMate's test harness.

---

### BM-1: BixBench
**Full title:** BixBench: A Comprehensive Benchmark for LLM-based Agents in Computational Biology  
**Source:** arXiv:2503.00096 (FutureHouse); submitted Feb 28 2025, revised Oct 8 2025 (v3)  
**URL:** https://arxiv.org/abs/2503.00096  
**Code/Data:** https://github.com/Future-House/BixBench (Apache 2.0)

#### Evaluation design
- **53 scenarios** drawn from real computational biology publications (wet-lab and dry-lab tasks)
- Each scenario is expanded into **~296 open-answer sub-questions**
- Agent runs inside a **Docker container** pre-loaded with standard bioinformatics packages (pandas, scipy, scanpy, pysam, biopython, etc.) and the relevant dataset files
- Agent must read files, run analysis, produce an answer string
- **Scoring:** open-answer accuracy judged by a secondary LLM (GPT-4o) comparing agent answer to ground truth; also a multiple-choice version for easier automated scoring
- **No time limit** documented; agent has full tool use (bash, Python execution, file read)
- **Key finding:** ground truth errors were later discovered — see BM-2 for corrected version

#### Metrics
| Metric | Description |
|---|---|
| Open-answer accuracy | % questions where LLM judge rates answer correct (0/1) |
| MC accuracy | % multiple-choice questions answered correctly |

#### Published scores on BixBench (original)

| System | Open-answer | Notes |
|---|---|---|
| GPT-4o (baseline) | 17% | Reported in original BixBench paper |
| Claude 3.5 Sonnet (baseline) | ~17% | Reported in original BixBench paper |
| Biomni Lab (Phylo) | 52.2% | Phylo blog post, Feb 2026 [1] |
| Edison Analysis | 42.4% | Phylo blog post, Feb 2026 [1] |
| OpenAI Agents SDK | 38.5% | Phylo blog post, Feb 2026 [1] |
| Claude Code (Opus 4.6) | 39.5% | Phylo blog post, Feb 2026 [1] |

**[1]** Phylo. "Evaluating AI Agents in Biology." phylo.bio/blog/evaluating-ai-agents-in-biology. Feb 11, 2026.

---

### BM-2: BixBench-Verified-50
**Full title:** BixBench-Verified-50 (Phylo curated subset)  
**Source:** Phylo blog post, Feb 11 2026  
**URL:** https://phylo.bio/blog/evaluating-ai-agents-in-biology

#### Evaluation design
- Phylo identified three failure classes in original BixBench: (a) genuine agent knowledge gaps, (b) ambiguous questions, (c) **incorrect ground truth answers**
- Domain experts revised ambiguous questions and corrected ground truth
- Result is a **50-scenario subset** with clean, verified ground truth
- Same Docker-environment + LLM-judge methodology as BM-1
- **Important:** the 36-point jump (52% → 88%) for Biomni is largely attributable to corrected ground truth, not agent improvement — this is a significant caveat for anyone citing Verified-50 scores

#### Published scores on BixBench-Verified-50

| System | Score | Delta from original |
|---|---|---|
| Biomni Lab | **88.7%** | +36.5 pp |
| Edison Analysis | 78.0% | +35.6 pp |
| Claude Code (Opus 4.6) | 65.3% | +25.8 pp |
| OpenAI Agents SDK | 61.3% | +22.8 pp |

**Source:** Phylo blog post, Feb 11 2026 [1]

---

### BM-3: BiomniEval1
**Full title:** Biomni-Eval1  
**Source:** HuggingFace dataset `biomni/Eval1`, released Oct 13 2025 alongside Biomni-R0 technical report  
**URL:** https://huggingface.co/datasets/biomni/Eval1  
**Code:** `biomni.eval.BiomniEval1` class (Apache 2.0); already present in BioMate at `/home/yzhang/biomate/Biomni/biomni/eval/biomni_eval1.py`

#### Evaluation design
- **433 instances** across **7–10 biological reasoning tasks** (README says 10; HuggingFace card exposes 7 task types in current release)
- Format: Parquet file with columns `task_name`, `task_instance_id`, `question`, `answer`, `reward_function`
- **Scoring:** task-specific reward functions returning float 0.0–1.0; binary for most tasks (exact match or JSON match)
- Evaluation is **fully automated** — no LLM judge needed for most tasks
- **Task types:**
  1. `gwas_variant_prioritization` — given phenotype + GWAS summary stats, identify top variant
  2. `gwas_causal_gene_opentargets` — identify causal gene from GWAS context using OpenTargets
  3. `screen_gene_retrieval` — identify genes with strongest perturbation effects in CRISPR screens
  4. `lab_bench_seqqa` — molecular biology Q&A (cloning, primer design, restriction digestion, ORF ID)
  5. `rare_disease_diagnosis` — output JSON with OMIM ID given clinical description
  6. `crispr_delivery` — select optimal CRISPR delivery method given context
  7. `patient_gene_detection` — output JSON with causal gene list (Ensembl IDs)

#### Published scores on BiomniEval1

| System | Score (avg across tasks) | Notes |
|---|---|---|
| Biomni-R0-32B-Preview | Best on 7/10 tasks | Biomni-R0 technical report, Sep 2025 |
| Claude 4 (Anthropic) | Beaten on 7/10 by Biomni-R0 | Biomni-R0 technical report |
| GPT-5 (OpenAI) | Beaten on 7/10 by Biomni-R0 | Biomni-R0 technical report |
| Biomni (original) | rare_disease_diagnosis: 0.67 | bioRxiv May 2025 [2] |

No single aggregate score published for BiomniEval1; task-level scores only.

**[2]** Huang K, Zhang S, Wang H, et al. "Biomni: A General-Purpose Biomedical AI Agent." bioRxiv. 2025. doi:10.1101/2025.05.30.656746

---

### BM-4: BioAgentBench
**Full title:** BioAgent Bench: An AI Agent Evaluation Suite for Bioinformatics  
**Source:** arXiv:2601.21800, Jan 29 2026  
**URL:** https://arxiv.org/abs/2601.21800  
**Data:** Released alongside paper (public)

#### Evaluation design
- Focuses on **canonical bioinformatics pipeline execution**: RNA-seq differential expression, variant calling, metagenomics
- Agents are given a task description + input files and must produce correct output artifacts
- **Robustness testing** is the key novel dimension: each task has 4 controlled perturbation variants:
  1. Corrupted input files (truncated FASTQ, malformed VCF)
  2. Decoy files in the working directory (misleading filenames)
  3. Prompt bloat (extra irrelevant context injected into the task description)
  4. Missing intermediate outputs (agent must detect and regenerate)
- **Scoring:**
  - Pipeline completion rate: does the final output artifact exist and pass format validation?
  - LLM-graded progress: partial credit for intermediate correct outputs
  - Output validity: domain-specific correctness checks (e.g., variant count in expected range, DE genes overlap with known list)
- Frontier closed-source models **complete baseline tasks** but **all fail under at least 3/4 perturbation types**; open-weight models safer for private data

#### Metrics
| Metric | Description |
|---|---|
| Completion rate | % pipelines producing valid final artifact |
| Robustness score | Completion rate under perturbations (4 types, averaged) |
| LLM progress score | Partial credit 0–1 for pipeline progress |

#### Published scores

| System | Baseline completion | Robustness | Notes |
|---|---|---|---|
| Frontier closed-source (GPT-4o, Claude) | High | Fails 3+/4 perturbation types | BioAgentBench paper Jan 2026 |
| Open-weight models | Lower baseline | Comparatively safer | BioAgentBench paper Jan 2026 |

Exact numerical scores per system not fully extracted from paper; refer to BioAgentBench Table 2.

---

### BM-5: ScienceAgentBench
**Full title:** ScienceAgentBench: Toward Rigorous Assessment of Language Agents for Data-Driven Scientific Discovery  
**Source:** ICLR 2025; OSU-NLP-Group  
**URL:** https://osu-nlp-group.github.io/ScienceAgentBench/  
**Code/Data:** https://github.com/OSU-NLP-Group/ScienceAgentBench

#### Evaluation design
- **102 tasks** extracted from **44 peer-reviewed publications** across 4 domains: Bioinformatics (largest), Computational Chemistry, GIS, Cognitive Neuroscience
- Each task: agent must write a Python program (or shell commands) that reproduces a specific analysis step from the paper
- Tasks verified against **expert-written gold-standard implementations**
- **Scoring:** task success rate — program runs without error AND produces output that matches gold standard within tolerance
- Programs are **auto-executed** in a sandboxed Python environment; no human judge needed
- Difficulty correlates with program length: success drops sharply for programs >58 lines
- Agents are given the paper PDF (or excerpt) + dataset files

#### Metrics
| Metric | Description |
|---|---|
| Task success rate | % tasks where generated program produces correct output |
| Valid program rate | % programs that execute without fatal error |
| Program length | Correlation with success rate |

#### Published scores

| System | Task success rate | Notes |
|---|---|---|
| o1-preview + self-debug | **42.2%** | Best reported; ICLR 2025 [3] |
| GPT-4o + self-debug | ~35% | ICLR 2025 [3] |
| Claude 3.5 Sonnet | ~30% | ICLR 2025 [3] |
| Human programmer | ~85% (takes 2.5–3h/task) | ICLR 2025 [3] |

**[3]** Chen W, et al. "ScienceAgentBench: Toward Rigorous Assessment of Language Agents for Data-Driven Scientific Discovery." ICLR 2025.

---

### BM-6: SGI-Bench
**Full title:** SGI-Bench: Probing Scientific General Intelligence of LLMs  
**Source:** PDF in `/home/yzhang/biomate/research/benchmark_evaluation/Probing Scientific General Intelligence of LLMs.pdf`  
**Integration status:** ALREADY INTEGRATED — `sgi_bench_adapter.py` with 503 BioMate-relevant samples validated; datasets at `/home/yzhang/biomate/research/benchmark_evaluation/sgi_bench_datasets/`

#### Evaluation design
- **5 task types** mapped to the PIM (Perception–Idea–Movement) cognitive model:
  1. `SGI-DeepResearch` — multi-step literature + knowledge reasoning (Deliberation)
  2. `SGI-IdeaGeneration` — hypothesis/protocol generation (Conception)
  3. `SGI-DryExperiment` — code execution + scientific validation (Action/Code)
  4. `SGI-WetExperiment` — lab protocol generation + temporal/parameter accuracy (Action/Protocol)
  5. `SGI-Reasoning` — multi-step logical reasoning over scientific context (Perception)
- **10 scientific disciplines**: Life, Chemistry, Physics, Astronomy, Earth, Material, Neuroscience, Mathematics, Information, Energy
- BioMate-relevant subset: **503 samples** from Life + Chemistry disciplines
- **Scoring rubrics** (per task type):
  - Deep Research: `step_accuracy`, `final_answer_accuracy`, `reasoning_validity`
  - Idea Generation: `novelty`, `feasibility`, `workflow_coherence`
  - Dry Experiment: `execution_success`, `unit_test_pass_rate`, `scientific_correctness`
  - Wet Experiment: `sequence_similarity`, `parameter_accuracy`, `temporal_coherence`
  - Reasoning: `answer_accuracy`, `reasoning_validity`, `comparative_ability`

#### Published scores (from original SGI-Bench paper)
Scores vary by model and discipline; refer to original paper. BioMate's harness has not yet run live evaluation — validation passed on 20 samples with mock responses.

---

### BM-7: BioML-bench
**Full title:** BioML-bench: Evaluation of AI Agents for End-to-End Biomedical ML  
**Source:** bioRxiv, Sep 2025, v2 revised 2026; doi:10.1101/2025.09.01.673319  
**Code:** https://github.com/science-machine/biomlbench

#### Evaluation design
- **4 domains** with ML pipeline tasks: protein engineering, single-cell omics, biomedical imaging, drug discovery
- Each task: agent receives a specification document → must build a pipeline, implement models, submit predictions
- Predictions are graded by established ML metrics appropriate to each domain
- **Agents evaluated:** Biomni, STELLA (biomedical specialists); AIDE, MLAgentBench (generalists)
- No agent reaches human baseline in any domain

#### Metrics
| Domain | Primary metric |
|---|---|
| Protein engineering | Spearman correlation with experimental fitness |
| Single-cell omics | AUROC on cell state classification |
| Biomedical imaging | AUROC on pathology classification |
| Drug discovery | AUROC on ADMET property prediction |

#### Published scores

| System | Protein Eng | scRNA-seq | Imaging | Drug Disc | Notes |
|---|---|---|---|---|---|
| Human baseline | Best in all | Best in all | Best in all | Best in all | BioML-bench paper [4] |
| Biomni | Leads agents | Leads agents | — | Leads agents | BioML-bench paper [4] |
| STELLA | — | — | — | — | Comparable to Biomni |
| AIDE, MLAgentBench | Below specialist | Below specialist | — | — | Generalist penalty |

All agents < human baseline (exact numbers in paper Table 3).

**[4]** BioML-bench: Evaluation of AI Agents for End-to-End Biomedical ML. bioRxiv 2025. doi:10.1101/2025.09.01.673319v2

---

### BM-8: HeurekaBench (sc-HeurekaBench)
**Full title:** HeurekaBench: A Benchmarking Framework for AI Co-scientist  
**Source:** ICLR 2026; EPFL MLBio Lab (Brbić group); arXiv:2601.01678  
**URL:** https://brbiclab.epfl.ch/projects/heurekabench/

#### Evaluation design
- **sc-HeurekaBench** (single-cell subset relevant to BioMate):
  - Drawn from **22 Nature/Cell single-cell biology papers**
  - **50 open-ended questions (OEQs)** + **50 multiple-choice questions (MCQs)** per paper (1,100 total tasks)
  - Questions test scientific reasoning: interpreting results, predicting experimental outcomes, suggesting follow-up analyses
  - Scoring: MCQ = exact match; OEQ = LLM judge with rubric
- Framework is positioned as "AI Co-scientist" evaluation — not just execution but scientific reasoning

#### Published scores

| System | sc-HeurekaBench | Notes |
|---|---|---|
| Biomni | Best of 3 agents | ICLR 2026 [5] |
| CellVoyager | Second | ICLR 2026 [5] |
| BixBench-Agent | Third | ICLR 2026 [5] |

**[5]** Panigrahi SS, Videnović J, Brbić M. "HeurekaBench: A Benchmarking Framework for AI Co-scientist." ICLR 2026. arXiv:2601.01678

---

### BM-9: PharmaBench
**Full title:** PharmaBench: Enhancing ADMET benchmarks with large language models  
**Source:** Scientific Data (Nature portfolio), 2024; doi:10.1038/s41597-024-03793-0  
**Code/Data:** https://github.com/mindrank-ai/PharmaBench

#### Evaluation design
- **11 ADMET property datasets**, 52,482 total entries (processed from 156,618 raw entries across 14,401 ChEMBL bioassays)
- Properties covered: Absorption (Caco-2, PAMPA, oral bioavailability), Distribution (PPB, VD), Metabolism (CYP inhibition — CYP1A2/2C9/2C19/2D6/3A4), Excretion (t½), Toxicity (hERG, DILI, Ames)
- Standard ML benchmark format: train/test splits; molecules as SMILES
- **Scoring:** ROC-AUC for classification tasks; RMSE/Pearson for regression tasks
- Used by Mozi (Mar 2026) as orchestration accuracy evaluation; used by DrugAgent for PAMPA absorption (F1=0.92)

#### Published scores

| System | Task | Metric | Score | Source |
|---|---|---|---|---|
| DrugAgent | PAMPA absorption | F1 | 0.92 | arXiv:2411.15692 [6] |
| Mozi | Orchestration accuracy | Custom | SOTA | arXiv:2603.03655 [7] |
| Standard ML baselines | CYP, hERG, DILI | ROC-AUC | ~0.80–0.93 | PharmaBench paper [8] |

**[6]** Shi Y, et al. "DrugAgent: Automating AI-aided Drug Discovery Programming through LLM Multi-Agent Collaboration." arXiv:2411.15692. 2024.  
**[7]** (Mozi paper) arXiv:2603.03655. March 2026.  
**[8]** Zhu W, et al. "PharmaBench: Enhancing ADMET benchmarks with large language models." Scientific Data. 2024.

---

### BM-10: Galaxy Workflow Retrieval Benchmark
**Full title:** Towards LLM-Powered Task-Aware Retrieval of Scientific Workflows for Galaxy  
**Source:** arXiv, Nov 2025  
**URL:** https://arxiv.org/abs/2511.01757

#### Evaluation design
- **Task:** given a natural-language description of a bioinformatics analysis, retrieve the most relevant Galaxy workflow
- Galaxy workflow corpus annotated with **BERTopic semantic labels**
- **Queries:** synthetically generated by LLMs to be realistic user intents; some queries are deliberately long or ambiguous
- **Two-stage system:** dense embedding retrieval (FAISS) → LLM reranker (GPT-4o or Mistral-7B)
- **Scoring:** Top-k accuracy and relevance; standard IR metrics

#### Metrics
| Metric | Description |
|---|---|
| Top-1 accuracy | Correct workflow ranked first |
| Top-5 accuracy | Correct workflow in top 5 |
| MRR@5 | Mean reciprocal rank at 5 |

#### Published scores

| System | Metric | Score | Notes |
|---|---|---|---|
| BM25 keyword baseline | Top-5 | Lower bound | Nov 2025 paper |
| FAISS embedding only | Top-5 | Moderate | Nov 2025 paper |
| FAISS + GPT-4o reranker | Top-5 | **Best** | Nov 2025 paper |
| FAISS + Mistral-7B reranker | Top-5 | Close to GPT-4o | Nov 2025 paper |

Exact numerical values not published in abstract; refer to paper Table 2.

---

### BM-11: BioMed-AQA (via BioMedAgent)
**Full title:** BioMed-AQA (evaluation suite used in BioMedAgent paper)  
**Source:** Nature Biomedical Engineering, 2026; "Empowering AI data scientists using a multi-agent LLM framework"  
**URL:** https://www.nature.com/articles/s41551-026-01634-6

#### Evaluation design
- **327 diverse biomedical data analysis tasks** covering genomics, transcriptomics, proteomics, imaging, clinical
- Each task: agent receives a data analysis problem description + dataset reference; must produce correct analysis result
- Agents evaluated with iterative problem-solving dialogues and self-evolving memory banks
- **Scoring:** task success rate (binary: correct result produced or not)

#### Published scores

| System | Task success rate | Notes |
|---|---|---|
| BioMedAgent | **77%** | Nature Biomed Eng 2026 [9]; SOTA |
| Baseline LLM agents | <50% | BioMedAgent paper comparison |

**[9]** (BioMedAgent paper) Nature Biomedical Engineering. 2026. doi:10.1038/s41551-026-01634-6

---

### BM-12: BiomniBench-DataAnalysis v0
**Full title:** BiomniBench-DataAnalysis v0 (Phylo trace-based benchmark)  
**Source:** Phylo research page + Kexin Huang X post, Feb 2026  
**URL:** https://phylo.bio/research

#### Evaluation design
- **Trace-based evaluation** — scores the analytical *process*, not just the final answer
- **5 rubric dimensions** scored per trace:
  1. Data handling (correct ingestion, appropriate preprocessing)
  2. Tool/method selection (right tool for the task)
  3. Statistical rigor (correct test, appropriate assumptions)
  4. Source reliability (uses authoritative databases/references)
  5. Reasoning chain (logical coherence of steps)
- **15 preliminary tasks** (v0 — to be expanded)
- Human comparison: senior pharmaceutical scientists (benchmark reference)

#### Published scores

| System | Score | Notes |
|---|---|---|
| Senior pharma scientists | 68.5 | Human reference ceiling |
| Biomni Lab | **65.0** | Phylo blog Feb 2026 [1] |
| Junior scientists | 48.5 | Human floor reference |

This is the most directly relevant benchmark to BioMate's governed execution model — scoring *process quality*, not just final answer.

---

## Part 2 — Competitor Profiles

### C-1: Biomni / Phylo
**Organization:** Stanford (snap-stanford), spun out as Phylo (Feb 2026, $13.5M seed)  
**Papers:**
- Huang K et al. "Biomni: A General-Purpose Biomedical AI Agent." bioRxiv May 2025. doi:10.1101/2025.05.30.656746
- Li R et al. "Biomni-R0: Using RL to Hill-Climb Biomedical Reasoning Agents to Expert-Level." Technical report Sep 2025.

**Architecture:**
- E1 environment: Docker-based execution sandbox with 200+ bioinformatics tools
- Multi-actor graph: planning agent → tool agents → verification agent
- Biomni-R0: Qwen3-32B fine-tuned with end-to-end multi-turn RL on Biomni-E1 environment
- scverse integration (Jul 2025): scanpy, squidpy, scirpy, pertpy + 6 others

**Benchmark scores summary:**

| Benchmark | Score | Rank |
|---|---|---|
| BixBench original | 52.2% | #1 of 4 systems |
| BixBench-Verified-50 | 88.7% | #1 of 4 systems |
| BiomniEval1 | Best on 7/10 tasks (Biomni-R0) | #1 vs Claude 4, GPT-5 |
| sc-HeurekaBench | Best of 3 agents | #1 |
| BioML-bench | Leads agents in 3/4 domains | #1 agent |
| BiomniBench-DataAnalysis | 65.0/100 | Near senior pharma scientist (68.5) |
| BioMed-AQA | Not reported | — |

**What BioMate lacks vs Biomni:**
- RL-fine-tuned domain expert model
- Docker sandbox with 200+ tools natively available
- A released, citable benchmark (Biomni has Eval1; BioMate has none released yet)

**What BioMate has that Biomni lacks:**
- GOLD/SILVER/BRONZE evidence-graded QC governance
- Protocol-aware threshold profiles
- Interactive halt + human approval gate
- License-gated tool orchestration
- Per-turn billing/cost governance
- Prereq recovery across multi-turn conversations
- Bioconductor KB (15,641 curated steps)

---

### C-2: BioMedAgent
**Organization:** (Multi-institution, published Nature Biomed Eng 2026)  
**Paper:** "Empowering AI data scientists using a multi-agent LLM framework with self-evolving capabilities." Nature Biomedical Engineering 2026. doi:10.1038/s41551-026-01634-6  

**Architecture:**
- Supervisor-worker multi-agent hierarchy
- Self-evolving memory banks: agents store successful strategies and reuse them
- Iterative problem-solving: retry with updated strategy on failure
- Natural-language initiated, no domain-specific configuration

**Benchmark scores:**
| Benchmark | Score |
|---|---|
| BioMed-AQA (327 tasks) | **77%** — published SOTA |

**What BioMate lacks vs BioMedAgent:** Self-evolving strategy memory; SOTA 77% bar on BioMed-AQA.  
**BioMate's differentiation:** Human oversight gates; evidence-graded governance; BioMedAgent is fully automated.

---

### C-3: Mozi
**Organization:** (Drug discovery team, affiliation not disclosed)  
**Paper:** "Mozi: Governed Autonomy for Drug Discovery LLM Agents." arXiv:2603.03655. Mar 4, 2026.

**Architecture:**
- **Dual-layer:** Control Plane (governed supervisor-worker, role-based tool isolation, reflection-based replanning) + Workflow Plane (canonical drug discovery stages as stateful skill groups)
- Stages: Target-ID → Structure → Docking → ADMET → Lead Optimization
- Reflection-based replanning: agent evaluates its own output quality before proceeding
- Role-based isolation: each stage's agent cannot access tools outside its scope (prevents hallucination propagation)

**Benchmark scores:**
| Benchmark | Score |
|---|---|
| PharmaBench orchestration | SOTA — outperforms unconstrained agents |
| PDBbind rank order | Not quantified in abstract |

**What BioMate has that Mozi lacks:** HumanApproval gates; audit trail with citation evidence; cross-domain coverage; Bioconductor KB; billing.  
**What BioMate could adopt from Mozi:** Reflection-based self-evaluation before stage transitions; role-based tool isolation per pipeline stage.

---

### C-4: CellAtria (AstraZeneca)
**Organization:** AstraZeneca  
**Paper:** "An agentic AI framework for ingestion and standardization of single-cell RNA-seq data analysis." npj Artificial Intelligence. 2025. doi:10.1038/s44387-025-00064-0  
**Code:** https://github.com/AstraZeneca/cellatria (open-source)

**Architecture:**
- Graph-based multi-actor: document parser → metadata extractor → CellExpress pipeline orchestrator → report generator
- CellExpress: Scanpy-based pipeline (QC, normalization, clustering, cell-type annotation via scType/SingleR)
- Chatbot interface for parameter adjustment
- Fully automated: no human approval gates

**Benchmark scores:** Reproducibility/automation demonstrated on internal AstraZeneca datasets; no public benchmark numbers published.

**BioMate differentiation vs CellAtria:** BioMate covers 14 domains (CellAtria = scRNA-seq only); BioMate has governance layer; CellAtria is fully automated with no evidence grading.

---

### C-5: GalaxyMCP
**Organization:** Galaxy Project (galaxyproject)  
**Code:** https://github.com/galaxyproject/galaxy-mcp (released 2025)

**Architecture:**
- Official Model Context Protocol (MCP) server for Galaxy
- Any MCP-compatible LLM (Claude, GPT-4) connects to Galaxy via standard protocol
- Capabilities: natural-language tool search, job execution, workflow management, Job Error Wizard (LLM job-failure explanation)
- Underneath: BioBlend API (same as BioMate's Galaxy integration)

**Threat level: HIGH** — a user can attach Claude directly to any Galaxy instance with zero integration cost.  
**BioMate's post-GalaxyMCP moat:** Protocol-aware governance; LLM routing across 14 domains; prereq recovery; Bioconductor KB; billing; license gating — none of which GalaxyMCP provides.

---

### C-6: BioChatter
**Organization:** Heidelberg/EMBL-EBI  
**Paper:** "A Platform for the Biomedical Application of Large Language Models." Nature Biotechnology 2025. doi recorded in PMC12216031  
**Code:** https://github.com/biocypher/biochatter (latest: v0.14.2, Feb 25 2026)

**Architecture:**
- Open-source Python framework: LLM + BioCypher knowledge graph + bioinformatics tool RAG
- BioCypher KG enables structured reasoning over protein interaction, disease pathway, and ontology data
- Modular: swap in any LLM backend (OpenAI, Anthropic, local)
- No execution environment — generates workflows/scripts, does not run them

**What BioMate has that BioChatter lacks:** Execution layer (Galaxy + Nextflow); governance; billing; prereq recovery; KG is execution-linked (BioMate KB steps are linked to runnable Galaxy/Nextflow tools).

---

### C-7: AutoBA
**Organization:** Multi-institution (published 2024–2025)  
**Paper:** "An AI Agent for Fully Automated Multi-Omic Analyses." PMC11600294. 2024.

**Architecture:**
- Single LLM agent: propose plan → generate code → execute → iterate
- Covers: WGS, WES, ChIP-seq, RNA-seq, scRNA-seq, spatial transcriptomics
- 3 user inputs only: data path, description, objective
- Fully automated, no human approval

**BioMate differentiation:** Governance; evidence-graded thresholds; license gating; domain-specialist guidance; billing.

---

### C-8: DrugAgent
**Paper:** "DrugAgent: Automating AI-aided Drug Discovery Programming through LLM Multi-Agent Collaboration." arXiv:2411.15692. Nov 2024.

**Benchmark scores:**
| Task | Metric | Score |
|---|---|---|
| Drug-target interaction (DTI) | ROC-AUC | +4.92% vs ReAct baseline |
| PAMPA absorption (ADMET) | F1 | **0.92** |
| Molecular property prediction | — | Matches expert-written code |

---

## Part 3 — Master Score Table

Rows = systems. Columns = benchmarks. Blank = not evaluated or not published.

| System | BixBench orig | BixBench-V50 | BiomniEval1 | BioAgentBench | SciAgentBench | SGI-Bench | BioML-bench | HeurekaBench | PharmaBench | BioMed-AQA | DataAnalysis |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Biomni Lab** | 52.2% | 88.7% | Best 7/10 | — | — | — | Leads agents | #1 | — | — | 65.0 |
| **BioMedAgent** | — | — | — | — | — | — | — | — | — | **77%** | — |
| **Mozi** | — | — | — | — | — | — | — | — | SOTA | — | — |
| **DrugAgent** | — | — | — | — | — | — | — | — | DTI+PAMPA | — | — |
| Claude Code Opus 4.6 | 39.5% | 65.3% | — | — | — | — | — | — | — | — | — |
| GPT-4o | 17% | — | — | — | ~35% | — | — | — | — | — | — |
| o1-preview | — | — | — | — | **42.2%** | — | — | — | — | — | — |
| **BioMate** | TBD | TBD | TBD | TBD | TBD | 503 samples validated | TBD | TBD | TBD | TBD | TBD |

**BioMate target scores (from benchmark strategy doc):**
- BixBench-Verified-50: ≥70% (gap to Biomni Lab 88.7% = 18.7 pp; gap to Claude Code 65.3% = +4.7 pp)
- BiomniEval1: competitive on bioinformatics-relevant tasks (GWAS, rare disease, scRNA-seq)
- BioAgentBench robustness: maintain completion under 3/4 perturbation types
- PharmaBench ADMET: ≥0.85 orchestration accuracy
- SGI-Bench life science: run full 503 samples

---

## Part 4 — Citation Index

| ID | Citation |
|---|---|
| [1] | Phylo. "Evaluating AI Agents in Biology." phylo.bio/blog/evaluating-ai-agents-in-biology. Feb 11, 2026. |
| [2] | Huang K, Zhang S, Wang H, et al. "Biomni: A General-Purpose Biomedical AI Agent." bioRxiv. May 2025. doi:10.1101/2025.05.30.656746 |
| [3] | Chen W, et al. "ScienceAgentBench: Toward Rigorous Assessment of Language Agents for Data-Driven Scientific Discovery." ICLR 2025. |
| [4] | BioML-bench: Evaluation of AI Agents for End-to-End Biomedical ML. bioRxiv. Sep 2025. doi:10.1101/2025.09.01.673319v2 |
| [5] | Panigrahi SS, Videnović J, Brbić M. "HeurekaBench: A Benchmarking Framework for AI Co-scientist." ICLR 2026. arXiv:2601.01678 |
| [6] | Shi Y, et al. "DrugAgent." arXiv:2411.15692. 2024. |
| [7] | Mozi authors. "Mozi: Governed Autonomy for Drug Discovery LLM Agents." arXiv:2603.03655. Mar 2026. |
| [8] | Zhu W, et al. "PharmaBench: Enhancing ADMET benchmarks with large language models." Scientific Data. 2024. doi:10.1038/s41597-024-03793-0 |
| [9] | BioMedAgent authors. "Empowering AI data scientists using a multi-agent LLM framework." Nature Biomedical Engineering. 2026. doi:10.1038/s41551-026-01634-6 |
| [10] | BixBench: arXiv:2503.00096. FutureHouse. Feb 2025. |
| [11] | BioAgentBench: arXiv:2601.21800. Jan 2026. |
| [12] | ScienceAgentBench: ICLR 2025. https://osu-nlp-group.github.io/ScienceAgentBench/ |
| [13] | Galaxy Workflow Retrieval: arXiv:2511.01757. Nov 2025. |
| [14] | CellAtria (AstraZeneca): npj Artificial Intelligence. 2025. doi:10.1038/s44387-025-00064-0 |
| [15] | BioChatter: Nature Biotechnology. 2025. PMC12216031. |
| [16] | AutoBA: PMC11600294. 2024. |
| [17] | Biomni-R0 technical report. biomni.stanford.edu/blog/biomni-r0-technical-report. Sep 2025. |
| [18] | BiomniBench-DataAnalysis v0: Phylo research page + Kexin Huang X post. Feb 2026. |
