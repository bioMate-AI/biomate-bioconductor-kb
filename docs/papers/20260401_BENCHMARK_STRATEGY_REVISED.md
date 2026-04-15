# BioMate Benchmark Strategy — Revised April 2026

**Supersedes:** `20260225_1545_MULTI_PAPER_PUBLICATION_STRATEGY.md` (benchmark sections only)
**Scope:** What benchmarks to run, what datasets to build, and how BioMate's evolving capabilities map to the current competitive landscape.

---

## 1. What Has Changed Since February 2026

### 1.1 New BioMate capabilities (since Feb 2026)
These are not reflected in any previous benchmark plan:

| Capability | Code location |
|---|---|
| Drug discovery pipelines: GROMACS, REINVENT4, Amber, Schrödinger, MOE, AlphaFold-DB | `backend/nextflow_workflows/drug_discovery/` |
| License/credential gate with per-tool routing (user vs BioMate key vs none) | `license_registry.py`, `credentials_api.py`, `license-gate.tsx` |
| LLM-based two-stage workflow search (intent classifier + semantic reranker) | `unified_workflow_search.py`, `galaxy-assistant.ts` |
| Prereq validation + recovery (multi-turn: user provides missing data mid-conversation) | `prereq-normalizer.ts`, `routes.ts` streaming endpoint |
| Stepwise approval gate — user sees and approves each pipeline stage before execution | `PipelineListView` S4 gate |
| Billing capture with per-turn cost tracking (Lago integration) | `billing/core/realtime_cost_service.py` |
| Bioconductor KB: 15,641 curated steps linked to Galaxy/Nextflow execution | `bioconductor_skill/` |
| Domain Specialist Guidance threaded into every response | S3 `DOMAIN_SPECIALIST_GUIDANCE` |

### 1.2 New competitive landscape (since Feb 2026)

| System | What it does | Threat to BioMate |
|---|---|---|
| **GalaxyMCP** (galaxyproject, 2025) | MCP server: any LLM (Claude, GPT) connects directly to Galaxy via standard protocol | HIGH — threatens the Galaxy integration moat entirely |
| **BioMedAgent** (Nature Biomed Eng, 2026) | Multi-agent biomedical data analysis, 77% success on BioMed-AQA | HIGH — sets new performance bar for general agents |
| **Mozi** (arXiv, Mar 2026) | Governed drug discovery agent (Target-ID → Lead-Opt) on PharmaBench | HIGH — direct competitor for drug discovery pipeline |
| **CellAtria** (AstraZeneca, npj AI, 2025) | Production scRNA-seq agent, fully automated, open-source | MEDIUM — beats BioMate's raw automation but has no governance |
| **BioAgentBench** (arXiv, Jan 2026) | Benchmark for RNA-seq, variant calling, metagenomics pipeline execution + robustness | LOW (benchmark, not platform) — we should evaluate on it |
| **BixBench** (FutureHouse, Feb 2025) | 53 real computational biology scenarios; frontier LLMs score 17% | LOW — establishes the baseline BioMate must beat |
| **BioChatter** (Nat Biotechnology, 2025, v0.14.2) | Open-source framework: LLM + BioCypher KG + bioinformatics databases | MEDIUM — architectural equivalent but no execution governance |

### 1.3 The critical threat: GalaxyMCP
GalaxyMCP means a user can attach Claude or GPT-4 directly to any Galaxy instance with zero integration cost. This obsoletes BioMate's Galaxy abstraction layer unless BioMate offers something beyond "talk to Galaxy":
- Protocol-aware QC governance with citation-backed thresholds
- Evidence-graded override permissions (GOLD/SILVER/BRONZE)
- Prereq validation and recovery across turns
- Cross-domain routing with 14 domain specialists
- License-gated tool orchestration
- Billing visibility and cost governance
- The Bioconductor KB step library (15,641 curated steps)

**These six capabilities are BioMate's post-GalaxyMCP moat.** The benchmark strategy must prove each one is real and measurable.

---

## 2. Existing Benchmarks BioMate Should Evaluate On

These are published, public benchmarks. Running BioMate against them provides credible third-party positioning.

### 2.1 BixBench (FutureHouse, arXiv Feb 2025)
- **What:** 53 real-world bioinformatics analysis scenarios (~296 open-answer questions); agent runs in a Docker environment with full bioinformatics tooling
- **Baseline:** GPT-4o and Claude 3.5 Sonnet score **17% open-answer accuracy**
- **Why BioMate should run it:** BioMate's domain specialist routing, prereq validation, and step-by-step approval should substantially raise the completion rate on structured tasks
- **Target claim:** BioMate achieves ≥40% on BixBench open-answer (2.4× frontier LLM baseline) due to guided execution architecture
- **Dataset:** GitHub FutureHouse/BixBench — open-source, runnable
- **Paper section:** System paper (Nature Methods), Section 3 — Guided Execution Benchmark

### 2.2 BioAgentBench (arXiv Jan 2026)
- **What:** RNA-seq, variant calling, metagenomics pipelines; completion rate + robustness under perturbations (corrupted inputs, decoy files, prompt bloat)
- **Why BioMate should run it:** The robustness dimension is where prereq validation and the approval gate should shine — BioMate should fail gracefully and recover, not silently corrupt outputs
- **Target claim:** BioMate maintains pipeline completion under 3/4 perturbation types where unconstrained agents fail all 4
- **Dataset:** Released alongside paper; public
- **Paper section:** System paper, Section 3 — Robustness under Perturbation

### 2.3 PharmaBench (Scientific Data / Nature, 2024)
- **What:** 11 ADMET datasets, 52,482 entries covering absorption/distribution/metabolism/excretion/toxicity
- **Why BioMate should run it:** BioMate now has ADMET workflows. Evaluate whether BioMate's end-to-end pipeline (user query → ADMET workflow selection → execution → result interpretation) matches/exceeds Mozi's reported accuracy on the same benchmark
- **Target claim:** BioMate selects the correct ADMET workflow type and interprets outputs for 85%+ of PharmaBench query types
- **Dataset:** github.com/mindrank-ai/PharmaBench — open-source
- **Paper section:** Drug discovery paper (Nature Chemical Biology), Section 3

### 2.4 Galaxy Workflow Retrieval Benchmark (arXiv Nov 2025)
- **What:** Dense-retrieval + LLM reranking for finding Galaxy workflows from natural-language task descriptions; BERTopic-annotated Galaxy workflows + LLM-generated queries
- **Why BioMate should run it:** BioMate's two-stage search (intent classifier → semantic reranker in `unified_workflow_search.py`) is architecturally identical to the benchmark's best system. The benchmark has a published top-k accuracy number to beat.
- **Target claim:** BioMate's two-stage search matches or exceeds the benchmark's best system (FAISS embedding + GPT-4o reranker) while operating on a significantly larger catalog (238+ Nextflow workflows vs Galaxy library)
- **Paper section:** KB paper (NAR Database Issue), retrieval evaluation section

### 2.5 ScienceAgentBench (ICLR 2025)
- **What:** 102 tasks from 44 peer-reviewed publications, including bioinformatics; best model (o1-preview) scores 42.2%
- **Why BioMate should run it:** The bioinformatics subset is a natural fit. BioMate's Bioconductor KB should improve function citation accuracy (88.2% KB-grounded vs 71.4% LLM-only — already measured in KB paper)
- **Target claim:** On the bioinformatics subset, BioMate outperforms o1-preview due to KB-grounded workflow generation
- **Dataset:** GitHub OSU-NLP-Group/ScienceAgentBench — open-source

### 2.6 BioMed-AQA (used by BioMedAgent, Nature Biomed Eng 2026)
- **What:** 327 diverse biomedical data analysis tasks; BioMedAgent achieves 77% success rate
- **Why BioMate should run it:** 77% is now the published state-of-the-art bar. BioMate's governance layer should trade some raw automation speed for higher reliability, but must demonstrate competitive success rate (target: ≥70% with lower hallucination rate on the 70%)
- **Note:** BioMed-AQA may be available via the BioMedAgent GitHub; confirm release status before committing to this benchmark

---

## 3. BioMate-Specific Benchmark Datasets to Build

These are datasets that don't exist publicly and that test BioMate's unique capabilities. Building and releasing them is itself a paper contribution.

### 3.1 QC Governance Benchmark (BioMate's core claim)

**What it tests:** Whether BioMate's GOLD/SILVER/BRONZE governance correctly catches QC failures that automated tools pass or silently filter

**Dataset construction:**
- Take 5 public datasets: ENCSR000AED (RNA-seq), GSE68086 (FFPE RNA-seq), GSE121893 (scRNA-seq), SRP047083 (metagenomics), ENCSR356LIU (ATAC-seq)
- For each, introduce 3 categories of controlled defects:
  1. **Silent quality failures** — rRNA contamination ≥30%, adapter dimers ≥15%, batch effects from protocol switch mid-cohort
  2. **Near-threshold ambiguity cases** — samples at 95% of threshold (should WARN, not FAIL)
  3. **Protocol-specific edge cases** — low-input library (low complexity is expected), FFPE (degradation is expected), phospho-enriched proteomics (lower peptide coverage is expected)
- Expert bioinformaticians label each case: correct action = PASS / WARN / FAIL + suggested_action

**Metrics:**
- Sensitivity (FAIL caught / actual FAILs)
- Specificity (correct PASSes / actual PASSes)
- Protocol-aware accuracy (edge cases where naive tools fail but BioMate succeeds)
- Override appropriateness: when human overrides a FAIL, is the suggested_action meaningful?

**Comparators:** MultiQC standalone, nf-core default QC, CellAtria (for scRNA-seq)

**Target claim:** BioMate achieves ≥90% sensitivity with ≥20% fewer false FAILs than MultiQC on protocol-specific edge cases

**Release:** 100 labeled samples + evaluation scripts as a public dataset (Zenodo); include in Nature Methods paper as Table 2

---

### 3.2 Prereq Recovery Benchmark

**What it tests:** When a user starts an analysis without providing required input files or accessions, can the system correctly identify what's missing, ask for it once, and successfully continue — across multi-turn conversations?

**Dataset construction:**
- 40 multi-turn dialogue trajectories across 4 domains (RNA-seq, variant calling, drug docking, proteomics)
- Each trajectory has:
  - Turn 1: underspecified query (e.g., "run germline variant calling for my patient" — no file, no accession)
  - Turn 2: partial response (user provides wrong file format)
  - Turn 3: correct resolution (user provides SRR accession)
- Outcomes labeled: RESOLVED (workflow ran successfully), UNRESOLVED (system gave up or hallucinated a path), LOOP (system asked the same question >2 times)

**Metrics:**
- Resolution rate: % trajectories where workflow successfully launched
- Turns-to-resolution: average turns needed
- Redundant-question rate: % trajectories where system asked for info already provided
- Recovery success after wrong-format input: % handled correctly

**Comparators:** Raw Claude 3.5 Sonnet with Galaxy MCP, raw GPT-4o, BioAgentBench baseline (no recovery mechanism)

**Target claim:** BioMate resolves 85%+ of multi-turn prereq trajectories in ≤2 turns; raw LLM + GalaxyMCP resolves <40%

**Release:** 40 annotated dialogue trajectories (JSON format); evaluation harness; include in system paper

---

### 3.3 Cross-Domain Workflow Routing Accuracy Benchmark

**What it tests:** Given a natural-language query, does BioMate select the correct workflow category and specific workflow on the first try, across 14 domains?

**Dataset construction:**
- 150 natural-language queries authored by domain experts (10-12 per domain)
- Domains: RNA-seq, scRNA-seq, ATAC-seq, WGS/WES, metagenomics, proteomics, cryo-EM, drug discovery (docking), drug discovery (MD), ADMET, structure prediction, pharmacogenomics, methylation, pathway analysis
- Each query has: correct_workflow, acceptable_alternatives (list), disqualified_workflows (explicitly wrong, e.g., somatic pipeline for germline query)
- Three difficulty levels: direct (domain/method named), indirect (described by biology), adversarial (confusable domain pairs)

**Metrics:**
- Top-1 accuracy: correct workflow ranked first
- Top-3 accuracy: correct workflow in top 3
- Adversarial accuracy: score on confusable pairs only (germline vs somatic, ATAC vs ChIP-seq, GROMACS vs REINVENT4)
- Domain misrouting rate: workflow from wrong domain selected

**Comparators:** Galaxy MCP (raw LLM search), keyword BM25 baseline, BioChatter RAG

**Target claim:** BioMate achieves ≥80% Top-1 accuracy vs <50% for raw LLM + GalaxyMCP; adversarial accuracy ≥70% vs <35% for baselines

**Release:** 150 annotated queries + evaluation script; include in system paper and KB paper

---

### 3.4 Protocol-Aware Threshold Profile Benchmark

**What it tests:** BioMate's unique ability to apply different QC thresholds based on sample type, library preparation, and protocol — vs tools that apply universal thresholds

**Dataset construction:**
- Select 20 published datasets where the "correct" QC call depends on knowing the protocol:
  - Low-input scRNA-seq (10x Chromium Flex) — low unique molecular identifiers (UMIs) are expected
  - FFPE RNA-seq — high ribosomal RNA and degradation is expected
  - Phosphoproteomics — low peptide coverage is expected
  - Membrane protein cryo-EM — high background density is expected
  - Plasma proteomics — low dynamic range is expected
- Each dataset has: ground_truth_protocol, correct_threshold_profile, naive_universal_threshold
- Label whether naive universal threshold generates a false alarm (FAIL on a valid sample) or false pass (PASS on a defective sample)

**Metrics:**
- False alarm rate: naive vs protocol-aware (should be lower for BioMate)
- False pass rate: naive vs protocol-aware (should be lower for BioMate)
- Protocol inference accuracy: does BioMate correctly identify the protocol from metadata?

**Target claim:** Protocol-aware profiles reduce false QC alarms by ≥35% on FFPE, low-input, and specialized library types vs universal thresholds

**Release:** 20 annotated datasets + threshold comparison table; featured in Nature Methods paper as Figure 3

---

### 3.5 Audit Trail FAIR-Reproducibility Benchmark

**What it tests:** Whether BioMate's JSONL audit trail enables an independent researcher to exactly reproduce a published analysis, including QC decisions and any human overrides — something no competitor provides

**Dataset construction:**
- Run 10 complete analyses in BioMate (2 per domain: RNA-seq, scRNA-seq, proteomics, drug discovery, cryo-EM)
- Export audit trail for each (GOLD/SILVER/BRONZE evidence citations, override events, parameter decisions, tool versions)
- Hand audit trails to 3 independent researchers not involved in the original run
- Ask them to reproduce the analysis using only the audit trail + public data

**Metrics:**
- Reproducibility rate: % analyses reproduced to identical outputs (bitwise or tolerance-matched)
- Decision traceability: % QC decisions with recoverable cited evidence
- FAIR score: FAIRsoft assessment of the audit trail format
- Reproduction time: hours required vs hours with MultiQC/nf-core outputs only

**Target claim:** BioMate audit trails enable 90%+ exact reproduction; MultiQC/nf-core outputs enable <40% reproduction due to absent decision provenance

**Release:** 10 audit trail files (JSONL, anonymized) + reproduction harness; featured in governance paper

---

### 3.6 Drug Discovery End-to-End Pipeline Benchmark

**What it tests:** Full drug discovery pipeline from target to lead: structure prediction → docking → MD → ADMET → interpretable report; benchmarked against PharmaBench + PDBbind + public docking datasets

**Dataset construction:**
- 15 publicly characterized protein-ligand systems where experimental ΔG binding is known (from PDBbind or ChEMBL)
- For each: run BioMate's full pipeline (AlphaFold-DB search → Schrödinger Glide docking → GROMACS MD → ADMET via PharmaBench predictions)
- Compare BioMate's predicted rank order of ligands vs experimental rank order

**Metrics:**
- Spearman correlation: predicted vs experimental ΔG binding rank (vs Mozi's reported correlation)
- ADMET accuracy: PharmaBench categories predicted correctly
- Pipeline completion rate: % of 15 systems where pipeline ran end-to-end without error
- Stepwise approval coverage: % pipeline stages where human reviewer was presented a meaningful approval decision
- Cost per complete pipeline run (Lago billing data)

**Comparators:** Mozi (PharmaBench scores from their paper), DrugAgent (DTI ROC-AUC), raw AutoDock Vina baseline

**Target claim:** BioMate's governed pipeline achieves Spearman ρ ≥ 0.65 on PDBbind rank order (competitive with Mozi); uniquely provides auditable GOLD/SILVER/BRONZE evidence for every prediction

**Release:** 15 system inputs + BioMate pipeline outputs + audit trails; featured in Nature Chemical Biology paper

---

### 3.7 License-Gated Tool Orchestration Benchmark

**What it tests:** No benchmark exists for this anywhere. When a user has credentials for some licensed tools (Schrödinger) but not others (MOE), and the requested workflow requires a licensed tool, does the system correctly route to available tools, clearly explain what's blocked, and suggest open-source alternatives?

**Dataset construction:**
- 30 queries requiring licensed tools, under 3 credential scenarios:
  - User has all required licenses
  - User has no licenses (BioMate falls back to open-source equivalents)
  - User has partial licenses (mixed routing required)
- Ground truth: correct_tool_selected, correct_fallback_suggested, user_blocked (should not happen silently)

**Metrics:**
- Correct routing rate: % queries routed to the right tool given credentials
- Silent failure rate: % times system attempted to use an unavailable tool (should be 0)
- Fallback quality: % times the open-source fallback is scientifically appropriate (expert-labeled)
- User confusion rate: % times the system's explanation of what's blocked was rated confusing by users

**Target claim:** 100% correct routing (0 silent failures); 85%+ scientifically appropriate fallbacks; this capability is entirely absent from all benchmarked competitors

**Release:** 30 query cases + credential scenarios as YAML; evaluation script; include as supplementary in system paper

---

## 4. Benchmark-to-Paper Mapping

| Benchmark | BioMate unique? | Paper target | Timeline |
|---|---|---|---|
| BixBench (external) | No | Nature Methods — system paper | Month 6 |
| BioAgentBench (external) | No | Nature Methods — robustness section | Month 6 |
| PharmaBench (external) | No | Nat Chem Bio — drug discovery paper | Month 18 |
| Galaxy Workflow Retrieval (external) | No | NAR Database Issue — KB paper | Month 5 |
| ScienceAgentBench (external) | No | Nature Methods — KB comparison | Month 6 |
| **QC Governance Benchmark** | **YES** | **Nature Methods — core claim** | **Month 4** |
| **Prereq Recovery Benchmark** | **YES** | **Nature Methods — multi-turn section** | **Month 4** |
| **Cross-Domain Routing Benchmark** | **YES** | **Nature Methods + KB paper** | **Month 3** |
| **Protocol-Aware Threshold Benchmark** | **YES** | **Nature Methods — Figure 3** | **Month 5** |
| **Audit Trail FAIR-Reproducibility** | **YES** | **Nature Methods — governance section** | **Month 6** |
| **Drug Discovery E2E Benchmark** | **YES** | **Nat Chem Bio** | **Month 18** |
| **License-Gated Orchestration Benchmark** | **YES** | **Nature Methods — supplementary** | **Month 4** |

---

## 5. Revised Claims for Peer Review

These are the claims that survive competitive scrutiny as of April 2026:

### Claims that hold (updated competitive analysis)

1. **Interactive halt with human approval at QC failure** — still genuinely novel. GalaxyMCP, BioMedAgent, CellAtria, AutoBA all operate fully automated. None implement a structured HALT → HUMAN_DECISION → CONTINUE gate.

2. **Evidence-graded governance (GOLD/SILVER/BRONZE)** — still entirely absent from all competitors, including Mozi (which has governance but no citation-quality evidence grading).

3. **Protocol-aware threshold profiles by sample type** — still absent from all evaluated systems. MultiQC, CellAtria, BioMedAgent all use universal thresholds.

4. **Prereq recovery across multi-turn conversations** — novel as an explicit, tested system mechanism. BioAgentBench shows raw agents fail under perturbation; BioMate's recovery loop is a tested countermeasure.

5. **Cross-domain routing accuracy across 14 domains** — BioChatter and GalaxyMCP have no domain-specialized routing. Biomni covers 8 domains but without domain specialist guidance threaded into responses.

6. **License-gated tool orchestration with fallback routing** — entirely absent from all benchmarked systems.

7. **Auditable cost tracking per pipeline run (Lago billing)** — entirely novel. No academic system reports per-run cost with this granularity.

### Claims to update or retire

- **"First real-time QC gates"** — retire (CryoSPARC Live 2019, Warp 2019 predate BioMate)
- **"Only system integrating Galaxy + Nextflow"** — weaken (GalaxyMCP integrates Galaxy natively; update to "Only system with governed orchestration across both Galaxy and Nextflow with domain-specialized routing")
- **"Best workflow search"** — change to "Architecture validated by peer-reviewed Galaxy retrieval benchmark; two-stage LLM search outperforms BM25 baseline by X% on our routing benchmark"

---

## 6. Immediate Next Steps (April–May 2026)

| Priority | Action | Output |
|---|---|---|
| P0 | Build cross-domain routing benchmark: 150 queries across 14 domains | JSON annotation file + eval script in `docs/benchmarks/routing/` |
| P0 | Run BioMate on BixBench top-20 tasks and record scores | Score table + analysis in `docs/benchmarks/bixbench_results.md` |
| P1 | Build prereq recovery benchmark: 40 multi-turn trajectories | Trajectories in `docs/benchmarks/prereq_recovery/` |
| P1 | Build QC governance benchmark: introduce controlled defects to 5 public datasets | Defect scripts + labels in `docs/benchmarks/qc_governance/` |
| P1 | Run BioMate on BioAgentBench RNA-seq + variant calling tasks | Completion + robustness results |
| P2 | Build protocol-aware threshold dataset: 20 protocol-edge-case samples | Annotation YAML in `docs/benchmarks/protocol_thresholds/` |
| P2 | Draft drug discovery E2E benchmark spec: 15 PDBbind systems | Spec doc in `docs/benchmarks/drug_discovery_e2e/` |
| P3 | Apply to BioMed-AQA access; run BioMate vs 77% BioMedAgent bar | Comparison table |
