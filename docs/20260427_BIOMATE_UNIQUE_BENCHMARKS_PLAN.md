# BioMate-Unique Benchmark Suite — Gap Analysis, Feasibility, and Plan

**Date:** 2026-04-27  
**Scope:** 11 BioMate-specific evaluation dimensions; comparison against published systems; versioning strategy

---

## Critical Issue: Existing Performance Numbers Are Misleading

Before the benchmark design, a correction. The current four-dimension report reports ±σ that is **mathematically wrong** for binary (0/1) scores. The reported std is `sqrt(p×(1-p))` — a property of the Bernoulli distribution that depends only on p, not on sample size. It tells you nothing about measurement uncertainty.

**Corrected numbers (95% Wilson CI, correct uncertainty measure):**

| Benchmark | n | Score | Reported ±σ (WRONG) | Correct 95% CI | SE |
|-----------|---|-------|---------------------|----------------|----|
| BiomniEval1 | 223 | 64.6% | ±47.8% | [58.1%, 70.6%] | ±3.2% |
| LABBench CS | 33 | 93.9% | ±23.9% | [80.3%, 98.3%] | ±4.2% |
| BixBench | 30 | 26.7% | ±44.2% | [14.2%, 44.5%] | ±8.1% |
| SGI-Bench | 367 | 21.0% | ±40.7% | [17.1%, 25.5%] | ±2.1% |
| Routing | 120 | 94.6% | ±22.6% | [89.0%, 97.4%] | ±2.1% |

**Additional data quality issues:**
1. **LABBench CS**: Tested 33 tasks; published benchmark uses all 41. Subset may be biased. Must run full 41 tasks with documented selection rationale.
2. **BixBench**: MCQ adaptation (n=30) vs published open-ended code execution (n=296). Not comparable to published 17%/9%. Need either proper open-ended eval or clearly disclose MCQ format.
3. **Routing, License Gating, QC Thresholds**: Built from BioMate's own data — internal regression tests, not comparable to external systems.
4. **SGI-Bench**: We report binary accuracy; published SGI-Score is multi-dimensional (0–100). Incomparable as-is.
5. **BixBench n=30**: SE = ±8.1%, CI = [14%, 45%]. Too wide for meaningful claims. Need n≥100 for ±5% SE.

**Action items before any publication:**
- Replace ±std with 95% Wilson CI in all reports (fix pushed to `generate_eval_report.py`)
- Run full LABBench 41-task CloningScenarios
- Implement proper open-ended BixBench evaluation or explicitly label "MCQ adaptation"
- Separate "external comparison benchmarks" from "internal regression benchmarks" in all tables

---

## The 11 Dimensions: Current State, Gaps, and Plan

### 1. Routing (Workflow Selection)

**Current state:** v11, 120 tasks, 94.6% [89.0%, 97.4%]  
**Built from:** BioMate's own workflow DB — internal regression, not external comparison

**Published closest:** Galaxy Workflow Retrieval (arXiv:2511.01757, Nov 2025)  
- Same task class: NL query → workflow retrieval from catalog  
- Their corpus: ~200 Galaxy workflows; BioMate: 2,455 across 34 domains  
- They report FAISS+GPT-4o reranker as best but no quantitative numbers  

**What other tools can be tested on:**  
- TaskBench (arXiv:2311.18529): Tests tool selection F1 on HuggingFace/multimedia catalog (~6k tools). GPT-4 ≈ 65%. **Adaptable**: can convert our 120 routing queries to TaskBench format (NL query → correct tool selection) to give a like-for-like comparison. Limitation: their tools are general-purpose, not bioinformatics.  
- BFCL: Tests function call accuracy once the tool is selected. Not routing, but BioMate's routing+parameter pipeline maps to BFCL's multi-step categories.

**Key gap:** No published benchmark runs retrieval over a 2,455-workflow **bioinformatics-specialist** catalog with adversarial confusable pairs (e.g., sarek vs variantcalling vs dualrnaseq all score high for "somatic variant calling").

**Feasibility:** HIGH — fully implemented. Needs:
- Complete the 120-task set with adversarial pairs (50+ tasks where 2+ workflows are plausible)
- Publish with explicit IR metrics: MRR, P@1, NDCG@3, Hit@5
- Add a "confusable pair" sub-category to highlight discrimination capability

**Version plan:** v11 → v12 (expand to 180 tasks, add adversarial pairs). Freeze v11 as the publication baseline.

---

### 2. IR Search (search_ranked)

**Current state:** MRR=0.847, P@1=0.742, NDCG@3=0.920, Hit@5=0.967 (routing_ir_v5)

**Published closest:** BEIR (Thakur 2021) — same metrics, completely different domain (document retrieval, not workflow catalogs). BEIR SOTA averages MRR ~0.50 on hard sets. BioMate's 0.847 appears strong by comparison but the tasks are not equivalent.

**Gap:** No published benchmark applies MRR/NDCG to **bioinformatics workflow catalog retrieval**. The metrics are directly comparable to IR literature, giving useful contextualization.

**Feasibility:** HIGH — fully implemented. Needs canonical test set release + annotation methodology documentation.

---

### 3. Prereq Recovery (Self-Healing)

**Current state:** prereq_recovery_v3; 97.5% resolution rate  
**Taxonomy:** RESOLVED | LOOP (repeated same ask) | FALSE_LAUNCH (ran without needed input)

**Published closest:**  
- **BioAgentBench** (arXiv:2601.21800, Jan 2026): Tests 4 perturbation types including "missing intermediate output." Frontier models fail ≥3/4 perturbation types. **Directly adaptable**: can run BioMate under the same 4 perturbation conditions for direct comparison.  
- SWE-Bench: Code-level repair (~49% SOTA), not conversational prerequisite recovery.

**Gap:** Multi-turn conversational recovery (detect missing prereq → ask once → re-route correctly) has no published benchmark. BioAgentBench uses single-step retries, not multi-turn dialog.

**Can other tools be tested?**  
Yes — BioAgentBench's 4 perturbation conditions can be run on Biomni, AutoGen, and LangChain-based agents. Run BioMate under those conditions to provide a publishable comparison.

**Feasibility:** HIGH for internal; MEDIUM for external comparison (requires implementing BioAgentBench perturbation protocol).

**Version plan:** v3 → v4 (add BioAgentBench perturbation format; 60 tasks, stratified by workflow domain and failure type).

---

### 4. License Gating

**Current state:** v5, 54 tasks, 98.1% [90.1%, 99.9%]

**Published closest:** None. License/entitlement enforcement in AI agents has no published benchmark.

**Can other tools be tested?** No — no other bioinformatics agent has software license/entitlement gating. License gating is BioMate-unique.

**Feasibility:** HIGH for internal regression. LOW for external comparison. Report it as a system correctness test, not a competitive benchmark.

**Version plan:** Stable at v5. Expand to 75 tasks (add edge cases: expired licenses, group licenses, trial licenses). **Do not compare to external systems.**

---

### 5. Memory Benchmark

**Current state:** 20 scenarios, 100% weighted score  
**Taxonomy:** A (recall), B (correction), C (baseline), T (temporal), S (synthesis), X (adversarial)  
**Aligned with:** LongMemEval (arXiv:2410.10813)

**Published closest:**  
- **LongMemEval** (Wu 2024): 5 sub-tasks including temporal reasoning. GPT-4o with memory ≈ 60-65%. **BioMate's taxonomy directly maps** — our scenarios can be scored using LongMemEval rubric for direct comparison.  
- **LoCoMo** (Maharana 2024): Multi-hop memory, GPT-4 ≈ 45%.

**Key novel contribution:** Type B (correction routing) — recalled corrections drive different **workflow routing decisions**, not just different text answers. LongMemEval measures fact recall; BioMate measures action changes driven by memory. No published equivalent.

**Can other tools be tested?**  
Yes — LongMemEval scenarios can be run on Biomni, ChatGPT with memory, Gemini with memory. Run our 20 scenarios on GPT-4o (with/without memory) for the ±45pp gain comparison.

**Feasibility:** HIGH for internal. HIGH for comparison against published systems using our scenario YAML.

**Version plan:** 20 → 40 scenarios (add 10 Type B routing-correction cases, 10 multi-session cases). Publish YAML for reproducibility.

---

### 6. Routing Consistency (3-Tier)

**Current state:** T1:91.7%, T2:93.8%/100%, T3:83.3%  
**Tier definition:**  
- T1: Exact same query twice → same workflow selected  
- T2: Rephrased query → same workflow (semantic match)  
- T3: Domain-paraphrased query (technical synonym) → same workflow

**Published closest:**  
- **ReliabilityBench** (arXiv:2601.06112): Tests consistency under perturbations; pass^k metric. GPT-4o drops from 96.9% (ε=0) to 88.1% (ε=0.2).  
- **SelfCheckGPT** (arXiv:2303.08896): Paraphrase consistency as a hallucination signal.  
- **"Hallucinations in Variance"** (arXiv:2601.07058): Semantic Stability = mean paraphrase-consistency.

**Gap:** Routing *decision* stability (same workflow of 2,455 selected) is a stricter definition than response text consistency. No published benchmark applies this to bioinformatics workflow selection.

**Can other tools be tested?**  
Partial — T1/T2 (same/rephrased query) can be run on Biomni and ChatGPT. T3 requires BioMate's 2,455-workflow catalog to make the task meaningful.

**Feasibility:** HIGH. Cite ReliabilityBench for methodology; BioMate's routing-decision stability metric is novel.

**Version plan:** Expand T3 to 60 paraphrase groups (from current ~20). Add T4: temporal consistency (same query 1 week apart).

---

### 7. QC AutoLoop Benchmark

**Current state:** 96.4% convergence in ≤3 iterations across 96 tests (ADMET/CYP-DDI/Docking/NCA-PK)

**QC thresholds (from `qc_trace_monitor.py` lines 31-57):**

| Metric | RED LINE threshold | Source |
|--------|-------------------|--------|
| reads_surviving_pct | ≥50% | Library QC standard |
| fit_quality | ≥0.5 | CTF estimation validity |
| mito_fraction_pct | ≤80% | Cell viability proxy |
| alignment_rate | ≥5% | Hard halt (species swap) |

**GOLD metrics (ENCODE4 / GATK Best Practices, not overridable):**
- `mapped_pct` ≥70% (GATK Best Practices)
- `tss_enrichment` ≥5 acceptable, ≥7 ideal (ENCODE4 ATAC-seq 2022)
- `nrf_score` ≥0.9 (ENCODE4)

**Drug discovery gates (ADMET, `parameter_suggester.py`):**
- hERG IC50: <1 μM = high risk, advisory; <0.1 μM = halt
- DILI category: "high" → DILI structural alert filter
- Ames: positive → mutagenicity flag
- Ro5: MW >500 or logP >5 → pharmacokinetic flag

**How the benchmark is built:**  
1. Each test case: a compound profile + a QC failure scenario (e.g., hERG IC50 = 0.3 μM)  
2. BioMate must: (a) detect the gate failure, (b) identify the remediation parameter, (c) re-run with corrected params, (d) confirm gate passage  
3. Convergence = gate pass within ≤3 iterations  
4. Scored: gate_pass@1, gate_pass@3, escalation_needed, false_positive_remediations

**Published closest:**  
- TDC ADMET Group (Therapeutics Data Commons): Gate definitions (hERG, DILI, etc.) but TDC measures model prediction accuracy, not agent iteration convergence.  
- No published benchmark measures FDA-threshold-driven iterative agent convergence. **Most novel of all 11 dimensions.**

**Can other tools be tested?**  
Hard — requires an agent that can run ADMET tools iteratively. Could test Biomni (it has ADMET tools) on the same gate-fail scenarios, but Biomni doesn't have BioMate's QC convergence loop.

**Feasibility:** HIGH for internal. LOW for external comparison. Strongest novelty claim in the paper.

**Version plan:** 96 → 150 tests (add 6 domains: protein MD stability gates, cryo-EM resolution gates, RNA-seq rRNA contamination gates). Publish threshold table with literature citations.

---

### 8. Protocol→Workflow Routing

**Current state:** Dataset exists (60 cases in `datasets/protocol_to_workflow/`); no benchmark run results found.

**What it tests:** Given a methods section excerpt from a published paper (or lab SOP), BioMate must select the correct Nextflow workflow AND extract relevant parameters.

**Published closest:**  
- LABBench ProtocolQA (MCQ format, tests protocol comprehension, not routing)  
- BioAgentBench (tests pipeline construction from natural language)

**Gap:** Protocol-text-to-workflow mapping (from a real methods section to a specific nf-core pipeline + parameter set) has no published benchmark.

**Can other tools be tested?**  
Yes — the 60 protocol texts can be sent to Biomni, ChatGPT, and Gemini to see which workflow they recommend. Scoring: exact workflow match + parameter overlap F1.

**Feasibility:** HIGH — dataset already exists, just needs a runner and scoring. Probably 2 hours to implement.

**Version plan:** Build runner `run_protocol_to_workflow.py` immediately. 60 → 100 cases (add ambiguous protocols requiring clarification).

---

### 9. Param Prefill (Slot-Filling)

**Current state:** 115 cases including 15 `param_name_disambiguation` cases. Score: 0.0 (suggests runner issue, not actual 0% accuracy).

**Published closest:**  
- **BFCL** (Berkeley Function Calling Leaderboard): AST-match on function arguments. GPT-4o: ~88% simple, ~60% multi-step parallel.  
- **API-Bank** (arXiv:2304.08244): API call accuracy across 3 complexity levels. GPT-4 ≈ 75% on L2.

**Key novel elements BioMate adds beyond BFCL/API-Bank:**
1. **Semantic normalization**: `hg38` = `GRCh38` = `human` = `Homo_sapiens` — all must map to the correct value
2. **must_not_fill penalty**: hallucinating a parameter for an under-specified query should be penalized
3. **Bioinformatics specificity**: 15-40 params per workflow with complex types (strandedness: forward/reverse/unstranded/auto)

**Can other tools be tested?**  
Yes — BFCL format can be used to test our 115 cases on GPT-4o, Claude, Gemini directly. Run them as function-call accuracy tests. This gives a direct GPT-4o vs BioMate comparison.

**Feasibility:** HIGH. The score of 0.0 is a runner bug (check param_prefill runner). Fix, re-run, then externalize on BFCL format.

**Action:** Fix and re-run param_prefill runner. Check why all 20 scores are 0.

---

### 10. QC Governance (Audit Trails)

**Current state:** Dataset spec exists (README), no execution implemented yet.  
**Design:** 50 labeled samples (5 GEO/ENCODE datasets × 10 defect variants). Requires data download + defect injection.

**Published closest:**  
- **BiomniBench-DataAnalysis** (Phylo, Feb 2026): Scores trace quality on a 5-dimension rubric. Biomni Lab ≈ 65/100; senior pharma scientist ≈ 68.5/100. **Closest published analog for trace quality.**  
- **FAIR principles** (Wilkinson 2016): Design framework, not a benchmark.

**Gap:** No published benchmark tests whether an AI agent's audit trail enables **independent reproduction** by a third party. BiomniBench scores trace quality as observed; BioMate's target is reproduction success rate ≥90%.

**Can other tools be tested?**  
Yes — BiomniBench-DataAnalysis protocol can be run on BioMate outputs for cross-system comparison.

**Feasibility:** MEDIUM — requires data download (~5GB), defect injection scripts, and 2-rater expert annotation. Estimated: 2 bioinformaticians × 2 days + 1 developer day. Not ready for current benchmarking.

**Version plan:** Phase 1 (this quarter): Build injection pipeline + get expert labels. Phase 2: Run BioMate + MultiQC + nfcore on labeled set. Phase 3: Compare vs BiomniBench-DataAnalysis scores.

---

### 11. Autofix / Self-Healing

**Current state:** autofix_benchmark_v1, 40 tasks, 92.3% [80.1%, 97.5%]

**Published closest:**  
- **SWE-Bench** (Jimenez 2024): Code-level bug repair, ~49% SOTA. **Adaptable**: BioMate's error messages + failed outputs can be formatted as SWE-Bench-style issue reports. Run SWE-Bench agents on BioMate's Nextflow error cases for direct comparison.  
- **InterCode** (Yang 2023, arXiv:2306.14898): Interactive code correction, GPT-4 ≈ 40%.  
- **BioAgentBench** robustness: Pipeline perturbation recovery.

**Gap:** Domain-specific autofix (fixing a Nextflow pipeline error in a bioinformatics context, understanding container issues, parameter type errors, missing file errors) is not covered by SWE-Bench or InterCode. The scientific domain knowledge required (e.g., fixing a "genome not found" error by suggesting the correct genome alias) is novel.

**Can other tools be tested?**  
Yes — the 40 autofix cases can be run through SWE-Bench agents (Devin, Claude 3.5 Sonnet + SWE) for comparison. The scenarios need reformatting as GitHub issue-style reports.

**Feasibility:** HIGH — existing dataset, existing runner. Expand to 100 tasks (add Nextflow-specific error types: missing container, incompatible tool versions, parameter type mismatches).

**Version plan:** v1 → v2 (100 tasks, 5 error categories). Run SWE-Bench agents on the same cases for cross-system comparison.

---

## Continuous Generation Strategy

For benchmarks to track continuous improvement, new test cases must be generated without contaminating existing evaluation sets.

**Versioning rules:**
1. Every benchmark has a frozen `vN` that is never modified after first use
2. New cases go into `vN+1` — never modify existing versions
3. Track which version was used for each reported score in `SCORES.md`
4. Auto-generated cases (from LLM) go through a validation pipeline before being added to any version
5. Human-reviewed cases are marked `reviewed: true` in YAML; LLM-generated cases are `reviewed: false`

**Auto-generation pipeline (for routing/consistency/param_prefill):**
```
generate_candidate → validate_against_workflow_db → check_not_in_existing_versions → human_spot_check → add_to_vN+1
```

**Contamination protection:**
- Routing: New queries must be semantically distinct from any existing query (cosine similarity < 0.9 in BGE embedding space)
- Param prefill: New cases must come from workflows NOT used in training any BioMate model
- Memory: New scenarios use different user personas and domains from existing ones

---

## Feasibility Summary

| Benchmark | Current state | External comparison? | Closest published | Novelty | Priority |
|-----------|--------------|---------------------|------------------|---------|----------|
| Routing | v11, 94.6% ✅ | Partial (Galaxy WF Retrieval) | arXiv:2511.01757 | High | Publish now |
| IR Search | MRR=0.847 ✅ | Methodology (BEIR) | BEIR | Medium | Publish now |
| Prereq Recovery | v3, 97.5% ✅ | Partial (BioAgentBench) | arXiv:2601.21800 | High | Run BioAgentBench comparison |
| License Gating | v5, 98.1% ✅ | None (unique) | None | N/A (internal) | Internal only |
| Memory | 20 scenarios ✅ | Yes (LongMemEval) | arXiv:2410.10813 | Medium | Run LongMemEval comparison |
| Routing Consistency | 3-tier ✅ | Partial (ReliabilityBench) | arXiv:2601.06112 | High | Publish now |
| QC AutoLoop | 96 tests ✅ | None | TDC (gate defs only) | **Highest** | Publish now (strongest novelty) |
| Protocol→Workflow | Dataset ready, no runner ⚠️ | Partial (BioAgentBench) | arXiv:2601.21800 | High | Build runner (2h) |
| Param Prefill | 115 cases, runner broken ⚠️ | Yes (BFCL) | BFCL leaderboard | Medium | Fix runner, run BFCL comparison |
| QC Governance | Spec only, no execution ❌ | Yes (BiomniBench) | Phylo Feb 2026 | High | Phase 1: data injection (1 week) |
| Autofix | v1, 92.3% ✅ | Partial (SWE-Bench format) | arXiv:2310.06770 | Medium | Run SWE-Bench agents on cases |

---

## Immediate Actions (Today)

1. **Fix param_prefill runner** — check why all 20 scores are 0.0
2. **Build `run_protocol_to_workflow.py`** — 2 hours, dataset exists
3. **Replace ±std with 95% Wilson CI** in `generate_eval_report.py` — done ✅
4. **Run full LABBench 41 tasks** — fix the 33→41 subset issue
5. **Run BioAgentBench comparison for Prereq Recovery** — run BioMate under 4 perturbation conditions

---

*Related docs:*
- `docs/20260427_FOUR_DIMENSION_EVAL_FRAMEWORK_PLAN.md`
- `docs/20260427_PUBLISHED_BENCHMARK_COST_SURVEY.md`
- `docs/20260427_BIOMATE_VS_PUBLISHED_COMPARISON.md`
