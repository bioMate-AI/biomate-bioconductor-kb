# Automated Discovery and Integration of Bioinformatics Tools from GitHub: A Six-Stage Pipeline and an Honest Evaluation of Where Automation Stops

**Authors:** BioMate Team (author list TBD)
**Target venue:** *Bioinformatics* (Application Note) — primary; *GigaScience* / *F1000Research* (Software Tool) — secondary.
**Status:** Draft — 2026-07-14. Production pipeline; evaluation reports measured production runs and identifies the wrapper-correctness gap as the open problem.

---

## Abstract

Bioinformatics tool catalogs (bio.tools, the Galaxy ToolShed, nf-core) are curated by hand and lag the ~thousands of tools published to GitHub each year. We present an **auto-update pipeline** that runs daily to discover new bioinformatics tools on GitHub, extract their metadata and citations, generate Galaxy XML wrappers and container specifications, validate them, and integrate the results into a platform tool database — plus generate reviewed blog posts for high-value tools. The pipeline has six stages (DETECT → FETCH → GENERATE → VALIDATE → TEST → INTEGRATE) with LLM-assisted feasibility filtering and blog-worthiness scoring. We report a candid evaluation from real production runs rather than aspirational targets. **Discovery and selection work well:** a single detection run surfaced 264 repositories in ~25 min, a multi-criteria quality score (code quality, documentation, containerization, recency, scientific evidence) partitions them into auto-add / review / reject tiers, and an LLM feasibility + blog-worthiness filter cleanly separates pipelineable tools from libraries and web apps (5/10 tools judged blog-worthy in a labeled batch). **The hard, unsolved stage is functional wrapper correctness:** across every recorded pipeline run the count of wrappers that passed execution testing was zero; a quality gate found 0/14 auto-discovered tools workflow-ready (parameters empty or dummy for 100% of them); and 8/16 initially integrated tools referenced non-existent Docker containers — a defect fixed to 15/15 valid only after integrating the BioContainers API for container resolution. We argue this negative result is the paper's most useful contribution: **automated discovery + metadata is tractable; automated generation of executable, parameter-complete wrappers is not yet, and that boundary — not a headline success rate — is what a reproducibility-focused community needs measured.** We specify the evaluation such a community should demand: tool-selection precision/recall against a curated reference, wrapper execution rate, expert quality ratings, and coverage overlap with bio.tools/ToolShed.

---

## 1. Introduction

### 1.1 The curation lag

Bioinformatics software is published faster than any hand-curated catalog can absorb it. bio.tools, the Galaxy ToolShed, and nf-core each rely on human submission and review; the median tool reaches a catalog months after its GitHub release, if ever. A platform that routes user intents to executable tools (BioMate routes over ~2,455 workflows and ~9,200 tools) is therefore always behind the literature. Automating discovery-to-integration is attractive — but only if the automation produces artifacts that actually run.

### 1.2 What "integration" honestly requires

Integrating a tool is not adding a database row. A usable integration needs: a correct command template, a *complete parameter schema* (so the platform can render a real input form), a *reachable container* (so the tool executes reproducibly), and evidence the wrapper runs on real data. Each is a distinct difficulty, and — as our evaluation shows — they do not fall together. A pipeline can be excellent at discovery and metadata while failing at the executable core.

### 1.3 Contributions

1. A **six-stage daily pipeline** (DETECT → FETCH → GENERATE → VALIDATE → TEST → INTEGRATE + blog generation) with LLM-assisted feasibility and blog-worthiness filtering, deployed in production.
2. A **candid evaluation from real runs** that separates what automation achieves (discovery, metadata, container *resolution*, selection) from what it does not (functional, parameter-complete wrappers).
3. A **container-correctness result**: naive `:latest` guessing yields 50% broken containers; BioContainers-API resolution fixes it to 100% valid in the tested batch.
4. A **specification of the rigorous evaluation** the field should require, none of which the current self-reported "100% / production" stage metrics satisfy.

---

## 2. Related work

**Tool catalogs.** bio.tools, the Galaxy ToolShed, and nf-core/modules are the community references; all are human-curated. Bioconda / BioContainers provide the reproducible container substrate our GENERATE stage resolves against. **Automated wrapper generation.** Galaxy's `planemo` scaffolds and tests wrappers but is developer-driven, not autonomous discovery. **LLM code/metadata generation.** The paper-to-code systems (DeepCode, Paper2Code; see companion manuscript) show LLMs can draft runnable code but do not address tool-catalog integration or wrapper parameter completeness. To our knowledge no prior system runs autonomous daily GitHub→catalog integration for bioinformatics with an execution-validated quality gate — and our own results explain why: the execution-validation step is where autonomy currently breaks.

---

## 3. System design

### 3.1 Pipeline

```
DETECT → FETCH → GENERATE → VALIDATE → TEST → INTEGRATE → (BLOG)
GitHub    docs+    Galaxy XML   XML       exec    DB row
          citations + container  checks    test    auto_discovered=1
```
Orchestrated by `scripts/run_pipeline.py`; scheduled daily at 02:00 UTC (`setup_cron.sh`) with `DAYS_BACK=1`, `MIN_STARS=10`, no limit, `ENABLE_TEST=0` by default (execution testing is expensive and, as Section 5 shows, currently low-yield). A yearly backfill mode uses `MIN_STARS=75` with month-by-month windows.

### 3.2 Stages

**DETECT** (`detect_github_tools.py`). Searches the GitHub REST API across 55+ bioinformatics topics and scores each repository on an additive 0–1 rubric: code quality ≤ 0.35 (CI/CD, tests, lint), documentation ≤ 0.20, containerization 0.10, recency ≤ 0.10, scientific evidence ≤ 0.35 (associated paper, citations), releases 0.05. Classification: > 0.8 auto-add, 0.5–0.8 human review, < 0.5 reject.

**FETCH** (`documentation_fetcher.py`, `citation_extractor.py`, `unified_metadata_extractor.py`). Pulls README, install instructions, dependency and container hints; extracts citations via the CrossRef API.

**Feasibility filter** (`llm_feasibility_checker.py`; hybrid rules + `claude-sonnet-4-5`). Rejects import-only libraries, web frameworks (Dash/Flask/Streamlit), workflow engines, and general-purpose libraries; keeps CLI tools that consume biological data and emit files. Returns `{suitable, reason, confidence, tool_type}`.

**GENERATE** (`galaxy_wrapper_generator.py`, `parameter_extractor.py`). Emits a Galaxy tool XML wrapper and resolves a container tag via the **BioContainers API** (quay.io) rather than guessing `:latest`.

**VALIDATE** (`validate_wrapper.py`). Six XML checks: syntax, required elements, command block, container accessibility, parameter usage, and tool-id format. This is a *syntactic* gate — it does not establish that the tool runs.

**TEST** (`test_tool_execution.py`, `tool_functionality_verifier.py`, `dependency_installer.py`, `real_test_data_fetcher.py`). Attempts container-based execution with fetched test data. Disabled by default.

**INTEGRATE** (`integrate_tools.py`, `duplication_detector.py`). Writes the tool to `galaxy_ai_tools.db` (`auto_discovered=1`) with duplicate detection.

**BLOG** (`blog_worthiness_evaluator.py` → `blog_post_generator.py` → `blog_review_agent.py`). An LLM (`claude-3-5-haiku`) scores blog-worthiness `{worthy, confidence, tool_type, biological_focus, recommended_action, suggested_title}`; worthy tools get a draft that a review agent iterates (≤ 5 iterations) until `quality ≥ 0.85` with no critical issues.

### 3.3 Quality gate

A weighted 0–1 tool-quality score (parameters 35%, requirements 20%, basic metadata 15%, inputs/outputs 15%, usage docs 10%, scientific context 5%) with a **production threshold of ≥ 0.85 (grade A−) and no blocking issues**. Blocking issues: empty/dummy parameters, no Docker container, missing basic metadata. This gate is the honesty mechanism — it is what reveals (Section 5) that auto-generated wrappers are not yet production-ready.

---

## 4. Evaluation methodology

We deliberately report **measured production runs** (JSON `pipeline_stats_*.json`, `quality_report_*.json`, container-verification logs, and a labeled blog-worthiness batch) rather than the aspirational "100% / production" figures that appear in internal status documents. Where a number is a modeled projection (throughput, $/tool) we label it as such and do not treat it as a result.

---

## 5. Results

### 5.1 Discovery and selection — automation works

- **Detection throughput.** One run surfaced **264 repositories** (87 high-quality > 0.8, 98 medium, 79 low) in **1,491 s (~25 min)**, GitHub-rate-limited.
- **Feasibility / blog-worthiness selection.** In a labeled 10-tool batch, the LLM filter judged **5 worthy** (ColabFold 0.90, foldseek 0.85, MMseqs2 0.85, graphein 0.80, omicverse 0.75) and **5 skipped** (biopython 0.95-confidence *skip* as a general library, seqkit, biotite, htslib, rush) — correctly separating pipelineable tools from libraries. The blog review loop moved a foldseek draft from quality 0.45 → 0.92 in 2 iterations.

These results support the claim that **discovery, metadata extraction, and selection are tractable and useful today**.

### 5.2 Wrapper correctness — the open bottleneck

- **Execution testing yields zero.** Across all recorded `pipeline_stats_*.json` runs (Nov 2025), the number of wrappers that **passed execution testing was 0** in every run; integrations succeeded only with testing disabled. Automated generation does not yet produce wrappers demonstrated to run.
- **Parameters are empty or dummy.** A quality-gate assessment of **14 auto-discovered tools found 0 workflow-ready**; 3 graded B+ (0.81–0.84), 7 D, 4 F, with missing/dummy parameters the blocking issue in **11/14**. For comparison, 96% of the ~9,200 hand-curated tools carry real parameters, versus **0–57%** meaningful (43% empty, 57% placeholder) for auto tools. Without a real parameter schema the platform cannot render a usable input form — the wrapper is a stub.
- **Containers: guessing fails, resolution works.** A verification of 16 integrated tools found **8/16 (50%) referenced non-existent Docker containers** (e.g. `colabfold:latest`, `foldseek:latest`). After integrating the **BioContainers API** for container resolution, a 15-tool batch achieved **15/15 valid containers** (0 `:latest`; 11 BioContainers + 4 language-runtime fallbacks), with 34/34 tests green across edge/unit/E2E/comprehensive suites. This isolates a concrete, fixable failure mode (name guessing) from the harder one (parameter completeness).

### 5.3 What the numbers mean

The pipeline is a **strong discovery-and-metadata engine with a stub-wrapper output.** The DETECT/FETCH/feasibility/blog stages produce genuinely useful artifacts; the GENERATE→TEST core produces wrappers that pass *syntactic* validation but fail *functional* readiness (no parameters, unverified execution). Reporting this boundary honestly is more valuable to the community than a self-graded "100%," because it says exactly where a human must still intervene and where research effort should go (parameter inference from docs; execution-in-the-loop generation).

---

## 6. The evaluation the field should demand

The current internal metrics (per-stage "100%", "87.5% completeness", "75% citation success") are script self-scores, not independent measurements. A reproducibility-focused venue should require:

1. **Tool-selection precision/recall** against a curated relevant-tool reference set, and inter-rater agreement on blog-worthiness labels (currently 10 LLM labels, no human gold standard).
2. **Wrapper execution rate** — fraction of generated wrappers that run to completion on real test data (currently 0 demonstrated).
3. **Parameter-completeness rate** — fraction with a non-dummy schema (currently 0/14 production-ready).
4. **Expert quality ratings** of integrated tools (currently none).
5. **Coverage/overlap vs. bio.tools and the Galaxy ToolShed** — what the pipeline finds that manual curation misses, and vice versa (currently only an unmethodized "95% vs 87.5%" table).
6. **Stable end-to-end yield with confidence intervals** — current integration counts are confounded by fixed bugs (SQLite schema mismatch, initializer error, all-tests-fail) and are single-run anecdotes.
7. **Duplicate-detection accuracy** against a labeled duplicate set (only one duplicate ever observed).

We present these as the roadmap, not as solved.

---

## 7. Discussion

**Where autonomy is real.** Continuous discovery, citation/metadata extraction, LLM feasibility triage, and BioContainers-grounded container resolution are production-viable and reduce human catalog effort.

**Where it is not.** Autonomous generation of *executable, parameter-complete* wrappers is unsolved. The root cause is that parameters live in prose (help text, `--flag` docs, examples) that current generation does not reliably parse into a typed schema, and that syntactic validation cannot catch functional emptiness. Execution-in-the-loop generation (generate → run → repair against real test data), analogous to AI-Scientist-v2's tree-search and to BioMate's QC auto-loop, is the promising direction — but it is expensive, which is why `ENABLE_TEST=0` today.

**Relationship to paper ingestion.** This pipeline and the paper-to-workflow module (companion manuscript) are two arms of the same capability-acquisition loop: one ingests GitHub tools, the other ingests published methods. Both deposit new capability into the same catalog, and both hit the same wall — turning a description into a *parameter-complete, executable* artifact — which suggests the parameter-inference problem is the shared, high-value research target.

---

## 8. Limitations

- Measured batches are small (largest real batch = 20 tools); throughput and cost figures are modeled projections, not benchmarked at scale.
- LLM feasibility/blog-worthiness error rates and stability are unmeasured.
- No human expert evaluation; no comparison methodology against bio.tools/ToolShed beyond an unmethodized table.
- Integration counts across historical runs are confounded by since-fixed bugs.

---

## 9. Conclusion

An autonomous GitHub→catalog pipeline for bioinformatics is achievable for *discovery, metadata, selection, and container resolution*, and we report real production evidence that these stages work. It is **not** yet achievable for *functional, parameter-complete wrapper generation* — every measured run demonstrates zero execution-validated, parameter-complete wrappers, and we present that boundary as the paper's central, honest finding. We specify the evaluation the field should require and identify parameter inference with execution-in-the-loop repair as the shared next problem for both tool and paper ingestion.

---

## Reproducibility

- Pipeline: `/home/yzhang/biomate/auto_update/` (scripts, `data/pipeline_stats_*.json`, `quality_report_*.json`, `blog_worthiness_results.json`)
- System doc: `docs/06-auto-update/20260112_AUTO_UPDATE_SYSTEM.md`; architecture: `docs/architecture/25_auto_update_pipeline.drawio.xml`
- Container-fix validation: `auto_update/FINAL_TEST_RESULTS_20251107.md`; verification: `auto_update/VERIFICATION_TEST_RESULTS_20251107.md`
- Quality gate: `auto_update/TOOL_QUALITY_GATE_SYSTEM_20251117_114300.md`
