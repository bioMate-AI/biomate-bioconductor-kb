# BioMate Evaluation Extension Plan
**Date:** 2026-04-01  
**Purpose:** Complete plan for extending the existing test harness into a full independent evaluation suite, building BioMate-unique benchmark datasets, identifying resource requirements, and providing a phased timeline.

---

## 1. What We Already Have

### 1.1 Core harness (production-ready)

| Component | File | Status |
|---|---|---|
| `BenchmarkSuite` | `test_harness/benchmark_suite.py` | Complete — checkpoint/resume, parallel runs, SQLite results DB |
| `CompositeEvaluator` | `test_harness/evaluators.py` | Complete — stackable ToolEvaluator + WorkflowEvaluator + ScientificEvaluator |
| `MetricsCollector` | `test_harness/metrics_collector.py` | Complete — CPU/memory/I/O + alignment/variant/expression quality metrics |
| `ResultsAnalyzer` | `test_harness/results_analyzer.py` | Complete — statistical tests, comparison reports, chart data |
| `UserBenchmarkContext` | `test_harness/user_context.py` | Complete — per-user/project/dataset evaluation context |
| SGI-Bench adapter | `test_harness/sgi_bench_adapter.py` | Complete — 503 life science samples loaded + scoring rubrics |
| SGI-Bench validation | `test_harness/validation_report.txt` | PASSED — 20/20 samples, all task types, all criteria |

### 1.2 Specialized evaluation systems (partially wired)

| Component | File | Status |
|---|---|---|
| `BiomniEval1` loader | `Biomni/biomni/eval/biomni_eval1.py` | Loader complete; **NOT wired into BenchmarkSuite** |
| Retrieval benchmark | `bioconductor_skill/skill_generation/20260303_retrieval_benchmark.py` | 50-task BM25 benchmark; standalone; **NOT wired into BenchmarkSuite** |
| Workflow quality evaluator | `research/scripts/evaluate_workflows.py` | Standalone; 100-point scoring; 65 trusted sources |
| Drug discovery pilot E2E | `frontend/e2e/drug-discovery-pilot-e2e.e2e.ts` | 6 sessions with per-turn timing + Lago billing — real execution data |
| `benchmark_knowledge.py` | `backend/lib/galaxy/ai/benchmark_knowledge.py` | SQLite DB with 100+ papers + tool metadata |

### 1.3 What is missing

1. **No BioMateEvalClient** — nothing submits tasks to the live BioMate API and captures responses for scoring
2. **No benchmark adapters** for BixBench, BioAgentBench, PharmaBench, ScienceAgentBench, BioML-bench, HeurekaBench
3. **No BioMate-unique benchmark datasets** (the 7 datasets described in benchmark strategy doc)
4. **SGI-Bench never run with live LLM** — only mock/validation mode
5. **BiomniEval1 never run** — loader exists but no runner script
6. **No runner orchestration script** — each benchmark runs in isolation with no unified entry point
7. **No competitive report generator** — results not automatically compared to published competitor scores

---

## 2. Extension Architecture

### 2.1 New files to create

```
backend/lib/galaxy/ai/test_harness/
├── biomate_eval_client.py         # NEW: HTTP client for BioMate API
├── llm_judge.py                   # NEW: Haiku-based judge for open-answer scoring
├── biomni_eval1_adapter.py        # NEW: wires existing loader into BenchmarkSuite
├── bixbench_adapter.py            # NEW: BixBench + BixBench-Verified-50
├── bioagentbench_adapter.py       # NEW: pipeline execution + robustness scoring
├── sciagentbench_adapter.py       # NEW: code generation + execution scoring
├── pharmabench_adapter.py         # NEW: ADMET workflow selection + accuracy
├── biomlbench_adapter.py          # NEW: scRNA-seq + drug discovery ML pipeline
├── heurekabench_adapter.py        # NEW: scientific reasoning on scRNA-seq papers
├── galaxy_retrieval_adapter.py    # NEW: extends existing retrieval benchmark
│
├── biomate_unique/                # NEW directory: BioMate-specific benchmark datasets
│   ├── qc_governance/             # Controlled-defect QC benchmark
│   ├── prereq_recovery/           # Multi-turn recovery benchmark
│   ├── cross_domain_routing/      # 150-query domain routing benchmark
│   ├── protocol_thresholds/       # Protocol-aware QC threshold benchmark
│   ├── audit_trail_fair/          # FAIR reproducibility benchmark
│   ├── drug_discovery_e2e/        # PDBbind-based drug discovery benchmark
│   └── license_gating/            # License-gated orchestration benchmark
│
└── runners/                       # NEW directory: benchmark runner scripts
    ├── run_all_benchmarks.py      # Master runner with --suite flag
    ├── run_biomni_eval1.py
    ├── run_bixbench.py
    ├── run_bioagentbench.py
    ├── run_sgi_bench_full.py      # Extends existing validate_sgi_bench.py
    ├── run_pharmabench.py
    └── generate_competitive_report.py
```

### 2.2 Unified runner interface

```bash
# Run a single benchmark
python -m galaxy.ai.test_harness.runners.run_all_benchmarks \
    --suite biomni_eval1 \
    --biomate-url http://localhost:8080 \
    --output results/

# Run all P0 benchmarks (quick, ~4h)
python -m galaxy.ai.test_harness.runners.run_all_benchmarks \
    --suite p0 \
    --biomate-url http://localhost:8080 \
    --output results/

# Generate competitive report
python -m galaxy.ai.test_harness.runners.generate_competitive_report \
    --results-dir results/ \
    --landscape docs/papers/20260401_COMPETITOR_BENCHMARK_LANDSCAPE.md
```

---

## 3. BioMate-Unique Benchmark Datasets

### 3.1 QC Governance Benchmark

**What it proves:** GOLD/SILVER/BRONZE evidence-graded QC catches failures that automated tools miss or over-report.

**Construction methodology:**

**Step 1 — Select base datasets (all public, no download cost):**
```
ENCSR000AED: RNA-seq, GM12878 cell line (ENCODE)
GSE68086:    FFPE RNA-seq, heterogeneous tumor samples
GSE121893:   scRNA-seq, cardiac tissue
SRP047083:   Metagenomics, soil samples
ENCSR356LIU: ATAC-seq, flagged quality in original paper
```

**Step 2 — Introduce controlled defects (3 categories per dataset):**

| Defect category | How to introduce | Expected BioMate action |
|---|---|---|
| rRNA contamination ≥30% | Spike in synthetic rRNA-mapped reads using `seqtk sample` | FAIL → suggest rRNA depletion |
| Adapter dimers ≥15% | Append adapter sequences to 15% of reads with `fastq_modifier.py` | FAIL → suggest trimming |
| Mid-cohort protocol switch | Relabel samples to swap library prep annotation | WARN → flag batch effect |
| Near-threshold (95% of limit) | Adjust read counts to land at 95% threshold | WARN (not FAIL) |
| FFPE degradation | Use GSE68086 FFPE samples with standard RNA-seq profile applied | PASS with protocol-aware profile |
| Low-input library | Simulate low UMI counts in scRNA-seq via subsampling | PASS (expected for low-input protocol) |

**Step 3 — Expert labeling:**
- 2 domain bioinformaticians label each sample: `{correct_action: PASS|WARN|FAIL, rationale, suggested_fix}`
- Inter-rater agreement measured (κ target ≥0.80)
- Disagreements resolved by third reviewer

**Step 4 — Comparator evaluation:**
- Run MultiQC standalone on same files → record PASS/WARN/FAIL
- Run nf-core default QC → record PASS/WARN/FAIL
- Compare all three (BioMate, MultiQC, nf-core) to expert ground truth

**Dataset size:** 5 base datasets × ~10 controlled-defect variants each = **~50 labeled samples**  
**Storage:** ~5 GB (FASTQ files; store defect-injected versions in S3)  
**Output files:** `biomate_unique/qc_governance/samples.json` (annotations), `inject_defects.py` (reproducible defect injection), `evaluate_qc.py` (scoring script)

**Resources needed:**
- 2 bioinformaticians × 2 days = 4 person-days for labeling
- AWS S3: ~$0.12/month for 5 GB
- EC2 for defect injection: t3.large, ~2h, ~$0.20

---

### 3.2 Prereq Recovery Benchmark

**What it proves:** BioMate recovers from missing/wrong prerequisites in multi-turn conversations; raw LLMs + GalaxyMCP fail.

**Construction methodology:**

**Step 1 — Define 40 dialogue trajectories across 4 domains (10 per domain):**

| Domain | Typical Turn-1 underspecification |
|---|---|
| RNA-seq | "Run differential expression for my cancer samples" — no files, no accessions |
| Variant calling | "Analyze my patient's genome for variants" — no BAM, no reference specified |
| Drug docking | "Dock ligands to my protein target" — no PDB ID, no SMILES |
| Proteomics | "Analyze my LC-MS data" — no mzML files, no experiment type specified |

**Step 2 — For each trajectory, define 3 turns:**
```yaml
# Example trajectory format (biomate_unique/prereq_recovery/trajectories.yaml)
- id: rna_seq_001
  domain: rna_seq
  turns:
    - role: user
      text: "Run differential expression analysis for my lung cancer RNA-seq data"
    - role: user
      text: "Here are my files"
      attachment_type: wrong_format  # provides PDF instead of FASTQ
    - role: user
      text: "SRR8562951,SRR8562952,SRR8562953"  # correct SRR accessions
  expected_outcome: RESOLVED
  max_turns_allowed: 3
  ground_truth_workflow: nf-core/rnaseq
```

**Step 3 — Run trajectories against BioMate + 2 baselines:**
1. BioMate (with prereq validation + recovery)
2. Raw Claude 3.5 Sonnet + GalaxyMCP (MCP-connected)
3. Raw GPT-4o (no Galaxy connection)

**Step 4 — Score each trajectory:**
- `RESOLVED`: workflow launched with correct parameters → 1.0
- `RESOLVED_EXTRA_TURNS`: resolved in >max_turns_allowed → 0.5
- `UNRESOLVED`: system gave up / hallucinated a file path → 0.0
- `LOOP`: asked for same information twice → 0.0
- `FALSE_LAUNCH`: launched with wrong data (silent failure) → -0.5

**Dataset size:** 40 trajectories × 3 turns = 120 conversation turns  
**Storage:** JSON file; trivial  
**Output files:** `biomate_unique/prereq_recovery/trajectories.yaml`, `run_prereq_benchmark.py`, `score_prereq.py`

**Resources needed:**
- 1 person-day to write 40 trajectories
- LLM API costs for 3 systems × 40 trajectories = ~$5

---

### 3.3 Cross-Domain Routing Accuracy Benchmark

**What it proves:** BioMate's two-stage LLM search outperforms raw GalaxyMCP on confusable multi-domain queries.

**Construction methodology:**

**Step 1 — 150 queries authored by domain experts (10–12 per domain):**

Domains: RNA-seq, scRNA-seq, ATAC-seq, WGS/WES, metagenomics, proteomics, cryo-EM, drug docking, drug MD, ADMET, structure prediction, pharmacogenomics, methylation, pathway analysis.

Difficulty levels:
- **Direct** (40%): domain/method explicitly named ("run DESeq2 differential expression")
- **Indirect** (40%): described by biology ("identify genes upregulated in drug-resistant cells")
- **Adversarial** (20%): confusable domain pairs (germline vs somatic, GROMACS vs REINVENT4, ATAC vs ChIP-seq)

**Step 2 — Annotation per query:**
```yaml
- id: routing_001
  query: "Identify somatic mutations in my tumor biopsy compared to normal tissue"
  difficulty: indirect
  correct_workflow: nf-core/sarek  # somatic variant calling
  acceptable_alternatives: [mutect2_workflow]
  disqualified_workflows: [nf-core/sarek_germline, deepvariant_germline]
  domain: variant_calling
  confusable_with: germline_variant_calling
```

**Step 3 — Evaluate 3 systems:**
1. BioMate two-stage search (existing `unified_workflow_search.py`)
2. Galaxy MCP raw LLM search (no domain specialist routing)
3. BM25 keyword baseline

**Metrics:** Top-1, Top-3 accuracy; adversarial accuracy; domain misrouting rate.

**This directly extends the existing retrieval benchmark** (`20260303_retrieval_benchmark.py`): that benchmark tests 50 queries for Bioconductor package retrieval; this tests 150 queries for Nextflow workflow retrieval. Same metric code, new queries.

**Dataset size:** 150 annotated queries (YAML file; trivial storage)  
**Resources needed:** 3 domain experts × 1 day each = 3 person-days for query authoring + annotation

---

### 3.4 Protocol-Aware Threshold Benchmark

**What it proves:** Protocol-specific QC profiles reduce false alarms by ≥35% on specialized library types.

**Construction methodology:**

**Step 1 — Select 20 published datasets with known protocol edge cases:**

| # | Dataset | Protocol | Universal threshold problem |
|---|---|---|---|
| 1–3 | GSE132044 (10x Genomics Flex) | Low-input scRNA-seq | Low UMIs → false FAIL |
| 4–6 | GSE68086 (FFPE tumor) | FFPE RNA-seq | High degradation → false FAIL |
| 7–9 | PXD004732 (phosphoproteomics) | TiO2 phosphoenrichment | Low peptide coverage → false FAIL |
| 10–12 | EMDB-16045 (membrane protein) | CryoEM membrane protein | High background → false FAIL |
| 13–15 | PXD010557 (plasma proteomics) | Serum depletion LC-MS | Low dynamic range → false FAIL |
| 16–18 | GSE176171 (FFPE spatial) | 10x Visium FFPE | Mixed FFPE + spatial issues |
| 19–20 | GSE150728 (low-input bulk) | Smart-seq3 very low-input | <1,000 reads/cell → false FAIL |

**Step 2 — For each dataset:**
1. Apply **universal QC threshold** (MultiQC defaults) → record decision
2. Apply **BioMate protocol-aware profile** → record decision
3. Expert bioinformatician labels **ground truth** (is this sample biologically valid or genuinely defective?)

**Step 3 — Compute:**
- False alarm rate (universal): samples labeled PASS by expert but FAIL by universal threshold
- False alarm rate (protocol-aware): same expert-PASS samples under BioMate profile
- Expected: BioMate false alarm rate ≤ 65% of universal false alarm rate (≥35% reduction claim)

**Dataset size:** 20 datasets × ~5–20 samples each = ~200 labeled samples  
**Storage:** ~10 GB raw data; ~200 MB processed QC stats  
**Resources needed:**
- 1 bioinformatician × 3 days for data download + QC run + labeling
- S3 for processed QC stats: ~$0.01/month

---

### 3.5 Audit Trail FAIR-Reproducibility Benchmark

**What it proves:** BioMate's JSONL audit trails enable exact reproduction by independent researchers; competitor outputs do not.

**Construction methodology:**

**Step 1 — Run 10 complete analyses in BioMate:**
```
2 RNA-seq (DESeq2, edgeR comparison)
2 scRNA-seq (cell type annotation, trajectory inference)
2 Proteomics (LC-MS/MS DIA analysis)
2 Drug discovery (docking + ADMET)
2 Structure prediction (AlphaFold-DB + Boltz-2)
```

**Step 2 — Export audit trails (JSONL format):**
Each audit trail contains:
- QC decision: `{step, criterion, evidence_level: GOLD|SILVER|BRONZE, citation_doi, decision, threshold_used, sample_value}`
- Override events: `{who, timestamp, justification, new_decision}`
- Parameter decisions: `{parameter_name, value_chosen, alternatives_considered, rationale}`
- Tool versions: `{tool_name, version, container_hash}`

**Step 3 — Distribute to 3 independent researchers:**
- Give them: audit trail JSONL + public dataset accession numbers
- Ask them to reproduce the analysis from scratch using only this information
- Time them; record reproduction success/failure per step

**Step 4 — Control condition:**
- Same 10 analyses run through nf-core (without BioMate governance layer)
- Outputs distributed to same 3 researchers: standard nf-core MultiQC report + output files
- Compare reproduction success rates

**Metrics:**
- Reproduction rate: % analyses reproduced to within tolerance
- Decision traceability: % QC decisions with recoverable cited evidence
- Reproduction time: hours per analysis

**Resources needed:**
- 3 independent bioinformaticians × 1 week each = 3 person-weeks
- Compensation: $200–$500/person (or academic collaboration)
- Compute for running the 10 analyses: ~$50 AWS

---

### 3.6 Drug Discovery E2E Benchmark

**What it proves:** BioMate's governed drug discovery pipeline achieves competitive Spearman rank correlation vs Mozi on PDBbind systems with a uniquely auditable trail.

**Construction methodology:**

**Step 1 — Select 15 protein-ligand systems from PDBbind General Set:**
Criteria:
- Experimental ΔG binding available (IC50 or Kd measured)
- Protein structure in PDB (for AlphaFold-DB search validation)
- Multiple ligands per target (to test rank order, not just single prediction)
- Diverse target classes: kinase (5), GPCR (3), protease (3), ion channel (2), NHR (2)

**Step 2 — Run BioMate full pipeline for each system:**
```
AlphaFold-DB search → structure retrieval
Schrödinger Glide docking (or AutoDock Vina fallback if no license)
GROMACS MD (1 ns quick run per ligand)
PharmaBench ADMET predictions
BioMate generates ranked ligand report
```

**Step 3 — Score:**
- Spearman ρ: BioMate rank vs experimental ΔG rank
- PharmaBench ADMET accuracy: fraction of ADMET predictions in correct bin (toxic/non-toxic)
- Pipeline completion rate: % of 15 systems completed end-to-end
- Stepwise approval coverage: % pipeline stages where meaningful human approval gate was presented
- Cost per pipeline run (from Lago billing data)

**Comparators:**
- Mozi (PharmaBench orchestration accuracy from paper)
- AutoDock Vina standalone (docking only, no governance)
- DrugAgent (DTI ROC-AUC)

**Resources needed:**
- Schrödinger trial license OR use AutoDock Vina (free, lower accuracy)
- 15 × GROMACS runs × 1 ns each: ~15 × 30 min GPU = ~8h; ~$5 on AWS Batch
- 1 domain chemist × 1 day to select PDBbind systems and validate results

---

### 3.7 License-Gated Orchestration Benchmark

**What it proves:** BioMate correctly routes tools based on available credentials with 0 silent failures; no competitor has this capability.

**Construction methodology:**

**Step 1 — 30 queries under 3 credential scenarios:**
```
Scenario A: Full licenses (Schrödinger + MOE + Amber)
Scenario B: No licenses (open-source fallbacks only)
Scenario C: Partial (Schrödinger only; MOE absent; Amber absent)
```

10 queries × 3 scenarios = 30 test cases.

**Step 2 — Annotation:**
```yaml
- query: "Run covalent docking of a cysteine-reactive warhead against my target protein"
  scenario_a_correct: moe_covalent_docking     # MOE available
  scenario_b_correct: autodock_covalent_free   # open-source fallback
  scenario_c_correct: autodock_covalent_free   # MOE not in partial set
  scenario_b_fallback_quality: GOOD            # expert-rated scientific appropriateness
```

**Step 3 — Run BioMate with each credential scenario (mock credential states):**
- Use `credentials_api.py` with injected credential states
- Record: tool selected, any error messages shown to user, whether fallback explanation was offered

**Step 4 — Score:**
- Correct routing rate: 100% target (0 silent failures)
- Fallback quality: expert rates whether fallback tool is scientifically appropriate (target ≥85%)
- User explanation quality: rated by non-expert user on 1–5 scale

**Resources needed:**
- 1 developer × 1 day to write 30 test cases + scoring script
- No external compute needed (mock credential states)

---

## 4. Resource Requirements Summary

### 4.1 People

| Role | Tasks | Estimated commitment |
|---|---|---|
| Backend developer (Python) | Adapters, BioMateEvalClient, LLM judge, runners | 20 dev-days |
| Domain bioinformatician ×2 | QC governance labeling (3.1), protocol threshold labeling (3.4) | 4 + 3 = 7 person-days |
| Independent reproducibility reviewers ×3 | Audit trail benchmark (3.5) | 3 person-weeks |
| Domain chemist | Drug discovery E2E PDBbind system selection (3.6) | 1 person-day |
| Expert query authors ×3 | Cross-domain routing queries (3.3) | 3 person-days |

**Total human effort:** ~30 dev-days + ~30 person-days (non-dev) + 3 person-weeks (reproducibility)

### 4.2 Compute

| Task | Resource | Cost estimate |
|---|---|---|
| SGI-Bench 503 samples (live LLM) | 1,000 API calls (Claude Haiku) | ~$10 |
| BiomniEval1 200 instances | 200 API calls | ~$5 |
| BixBench 300 questions + judge | 600 API calls | ~$20 |
| BioAgentBench 15 runs | EC2 t3.xlarge, ~3h | ~$2 |
| Cross-domain routing 150 queries | 150 API calls × 3 systems | ~$15 |
| Drug discovery E2E 15 systems | GPU (GROMACS): 8h g4dn.xlarge | ~$25 |
| QC defect injection + processing | EC2 t3.large, 2h | ~$1 |
| All other LLM calls | Various | ~$20 |
| **Total compute** | | **~$100** |

### 4.3 External data access

| Dataset | Access | Cost |
|---|---|---|
| BiomniEval1 | HuggingFace (free, Apache 2.0) | $0 |
| BixBench | GitHub (free, Apache 2.0) | $0 |
| BioAgentBench | Public release with paper | $0 |
| ScienceAgentBench | GitHub (free) | $0 |
| PharmaBench | GitHub (free) | $0 |
| SGI-Bench | Already downloaded (503 samples on disk) | $0 |
| BioML-bench | GitHub (free) | $0 |
| HeurekaBench | Email request to EPFL MLBio | $0 |
| Galaxy Workflow Retrieval | Email request to paper authors | $0 |
| PDBbind (for drug discovery E2E) | Free academic access | $0 |
| ENCODE, GEO datasets (for QC governance) | Free public access | $0 |
| **Total data cost** | | **$0** |

---

## 5. Phased Timeline

### Phase 1 — Quick wins (Month 1, April 2026)
**Goal:** Get BioMate's first scores on published benchmarks; establish comparative baseline.

| Week | Action | Output |
|---|---|---|
| Week 1 | Write `BioMateEvalClient` + `LLMJudge` | Shared infrastructure ready |
| Week 1 | Wire BiomniEval1 into BenchmarkSuite | Run 200 instances; get first score |
| Week 1 | Run SGI-Bench 503 samples with live LLM | SGI-Bench life science scores |
| Week 2 | Extend retrieval benchmark to 150 queries (cross-domain routing) | Routing accuracy vs GalaxyMCP |
| Week 2 | Write prereq recovery trajectories (40 trajectories) | Benchmark dataset complete |
| Week 3 | Write BixBench adapter; run on BioMate | BixBench score established |
| Week 3 | Write 30 license-gating test cases | Benchmark dataset complete |
| Week 4 | Run prereq recovery benchmark on all 3 systems | Comparative scores |
| Week 4 | Draft competitive report | Document BioMate vs Biomni on BiomniEval1 + BixBench |

**Deliverables:** BioMate scores on BiomniEval1, SGI-Bench, BixBench, routing benchmark. 3 unique benchmark datasets complete (prereq recovery, routing, license gating).

---

### Phase 2 — Robustness and uniqueness (Month 2, May 2026)
**Goal:** Complete the governance-specific unique benchmarks; run BioAgentBench.

| Week | Action | Output |
|---|---|---|
| Week 5 | Download + inject defects into 5 QC datasets | QC governance dataset ready |
| Week 5 | Recruit 2 domain bioinformaticians for labeling | Expert labeling begins |
| Week 6 | Write BioAgentBench adapter; run all 15 perturbation variants | Robustness scores |
| Week 6 | Expert labeling complete; compute inter-rater agreement | QC governance dataset finalized |
| Week 7 | Run MultiQC + nf-core on QC benchmark; compare all 3 | QC governance scores |
| Week 7 | Run ScienceAgentBench bioinformatics subset | ScienceAgentBench scores |
| Week 8 | Select 20 protocol-edge-case datasets; compute thresholds | Protocol threshold dataset |
| Week 8 | Run protocol threshold benchmark (BioMate vs universal) | Protocol-aware scores |

**Deliverables:** BioMate scores on BioAgentBench + ScienceAgentBench. QC governance + protocol threshold datasets complete with labeling.

---

### Phase 3 — Drug discovery and reproducibility (Month 3, June 2026)
**Goal:** Complete drug discovery E2E benchmark; run audit trail reproducibility study.

| Week | Action | Output |
|---|---|---|
| Week 9 | Select 15 PDBbind systems; run full drug discovery pipeline | Drug discovery E2E dataset |
| Week 9 | Obtain BioML-bench dataset; run scRNA-seq + drug discovery subtasks | BioML-bench scores |
| Week 10 | Run 10 complete analyses for audit trail benchmark | Audit trail JSONL files ready |
| Week 10 | Recruit 3 independent reproducibility reviewers | Reviewers briefed and begin |
| Week 11 | Run PharmaBench ADMET evaluation | PharmaBench scores |
| Week 11 | Reproducibility review in progress | — |
| Week 12 | Reproducibility review complete; compile scores | Audit trail benchmark scores |
| Week 12 | Contact EPFL for HeurekaBench dataset | — |

**Deliverables:** Full drug discovery pipeline benchmark. Audit trail reproducibility benchmark (most novel; requires most lead time for reviewer scheduling).

---

### Phase 4 — Paper-ready (Month 4–5, July–August 2026)
**Goal:** All benchmarks complete; paper drafts reference all scores.

- All 7 unique BioMate benchmark datasets released to Zenodo (DOIs for paper)
- Full competitive table (Part 3 of landscape doc) populated with BioMate scores
- HeurekaBench (if dataset obtained) run
- All results sections drafted for Nature Methods paper

---

## 6. How Existing Benchmarks → Unique BioMate Datasets

The key insight: each external benchmark has a **dimension it doesn't test** — which is exactly where BioMate is differentiated. BioMate's unique datasets are constructed by filling those gaps:

| External benchmark | What it doesn't test | BioMate-unique extension |
|---|---|---|
| BixBench | No human-in-the-loop; single-turn; no governance | → QC Governance Benchmark: adds QC halt + override decisions |
| BioAgentBench | Robustness via file corruption only; no multi-turn recovery | → Prereq Recovery Benchmark: multi-turn with wrong format + missing data |
| BiomniEval1 | No workflow selection or routing accuracy | → Cross-Domain Routing Benchmark: tests BioMate's 14-domain routing |
| PharmaBench | ADMET prediction accuracy only; no pipeline orchestration audit | → Drug Discovery E2E: adds governance, audit trail, cost per pipeline |
| ScienceAgentBench | Code generation only; no protocol-awareness | → Protocol-Aware Threshold Benchmark: same datasets, adds protocol metadata |
| BioML-bench | End-to-end accuracy only; no citation provenance | → Audit Trail FAIR Benchmark: same analyses, adds JSONL reproducibility audit |
| Galaxy Workflow Retrieval | Galaxy-only; no license-aware routing | → License-Gated Benchmark: adds credential states to routing decisions |

This framing is important for paper writing: BioMate's unique datasets are **not invented from scratch** — they are principled extensions of the benchmarks the community already uses, adding the governance dimension that no other system provides.

---

## 7. Paper Integration

| Unique benchmark | Section in Nature Methods paper | Figure/Table |
|---|---|---|
| QC Governance (3.1) | Section 3.2 — "Evidence-Graded QC Governance" | Table 2: BioMate vs MultiQC vs nf-core sensitivity/specificity |
| Prereq Recovery (3.2) | Section 3.3 — "Multi-Turn Prerequisite Recovery" | Figure 4: resolution rate + turns-to-resolution |
| Cross-Domain Routing (3.3) | Section 3.1 — "Domain-Specialized Workflow Search" | Table 1: Top-1/Top-3 accuracy by domain and difficulty |
| Protocol Thresholds (3.4) | Section 3.2 — "Protocol-Aware QC Governance" | Figure 3: false alarm rate reduction by protocol type |
| Audit Trail FAIR (3.5) | Section 3.5 — "Audit Trail and Reproducibility" | Table 4: reproduction rate BioMate vs nf-core |
| Drug Discovery E2E (3.6) | Nat Chem Bio paper Section 3 | Figure 2: Spearman correlation + cost per pipeline |
| License Gating (3.7) | Section 3.4 — "License-Gated Tool Orchestration" | Supplementary Table S1 |

External benchmarks map to:
| External benchmark | Paper section |
|---|---|
| BixBench / Verified-50 | Section 3.0 — "System Evaluation" baseline comparison |
| BiomniEval1 | Section 3.0 — comparison with Biomni on GWAS, rare disease |
| BioAgentBench | Section 3.3 — robustness under perturbation |
| ScienceAgentBench | Supplementary: KB-grounded code generation |
| SGI-Bench | Supplementary: general scientific reasoning |
| PharmaBench | Nat Chem Bio paper |
