# BioMate Test Harness Comprehensive Plan

**Document Version**: 1.0
**Date**: 2025-12-30
**Status**: Planning

---

## Executive Summary

This document outlines the comprehensive plan for BioMate's test harness system - a per-user, per-project quality assurance framework for scientific computing. The plan integrates SGI-Bench (Scientific General Intelligence Benchmark) as a simulation of real user needs to develop and validate the framework before production deployment.

### Key Principles

1. **User-Centric**: Test harness operates within each user's project context
2. **Data-Specific**: Evaluations run on user's actual datasets
3. **Holistic**: Assesses tools, workflows, LLM quality, and end-to-end results
4. **SGI-Bench as Simulation**: 407 expert-curated samples validate the framework
5. **Production-Ready**: Same infrastructure serves real users after validation

---

## Part 1: Architecture Overview

### 1.1 System Context

```
┌─────────────────────────────────────────────────────────────────────┐
│                         BioMate Platform                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │
│  │     User A      │    │     User B      │    │     User C      │  │
│  │    Projects     │    │    Projects     │    │    Projects     │  │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘  │
│           │                      │                      │           │
│           ▼                      ▼                      ▼           │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │
│  │  Test Harness   │    │  Test Harness   │    │  Test Harness   │  │
│  │   Instance A    │    │   Instance B    │    │   Instance C    │  │
│  │                 │    │                 │    │                 │  │
│  │ - Their data    │    │ - Their data    │    │ - Their data    │  │
│  │ - Their workflows│   │ - Their workflows│   │ - Their workflows│ │
│  │ - Their results │    │ - Their results │    │ - Their results │  │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              Shared Evaluation Framework                      │   │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐  │   │
│  │  │  SGI Criteria  │  │  Few-Shot      │  │  Evaluation    │  │   │
│  │  │  & Rubrics     │  │  Templates     │  │  Algorithms    │  │   │
│  │  └────────────────┘  └────────────────┘  └────────────────┘  │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 Test Harness Scope

The test harness evaluates **four levels** of the scientific computing stack:

| Level | What It Evaluates | Example Questions |
|-------|-------------------|-------------------|
| **Tool** | Individual tool performance | "How fast is STAR on my RNA-seq data?" |
| **Workflow** | Workflow design quality | "Are the steps correctly ordered and connected?" |
| **Scientific** | Scientific validity | "Are parameters appropriate for my organism?" |
| **End-to-End** | Final output quality | "Are the results biologically meaningful?" |

### 1.3 Per-User/Project Data Model

```
User
├── Profile (expertise, domain preferences)
├── Projects[]
│   ├── Project
│   │   ├── Metadata (name, domain, organisms, goals)
│   │   ├── Datasets[]
│   │   │   └── Dataset (path, type, size, samples)
│   │   ├── Workflows[]
│   │   │   └── Workflow (steps, parameters, generated_by)
│   │   └── TestHarness
│   │       ├── Config (evaluation preferences)
│   │       ├── Scenarios[] (custom test scenarios)
│   │       ├── Results[] (evaluation history)
│   │       └── Reports[] (generated reports)
│   └── ...
└── Preferences (default settings)
```

---

## Part 2: SGI-Bench as Simulation

### 2.1 Purpose of SGI-Bench Integration

SGI-Bench serves as a **simulation of real user needs** to:

1. **Validate Framework**: Ensure test harness handles real scientific complexity
2. **Develop Criteria**: Extract evaluation rubrics from expert-curated samples
3. **Stress Test**: 407 samples across Life Science + Chemistry domains
4. **Baseline Performance**: Establish benchmarks before real user deployment
5. **Few-Shot Library**: Expert examples improve BioMate's generation quality

### 2.2 SGI-Bench Dataset Summary

```
SGI-Bench Datasets (Downloaded)
Location: /home/yzhang/biomate/research/benchmark_evaluation/sgi_bench_datasets/

Dataset               │ Life Science │ Chemistry │ Total │ Task Type
──────────────────────┼──────────────┼───────────┼───────┼─────────────────────
SGI-DeepResearch      │      87      │    11     │   98  │ Literature synthesis
SGI-IdeaGeneration    │      87      │    11     │   98  │ Research proposal
SGI-DryExperiment     │      80      │     5     │   85  │ Code generation
SGI-WetExperiment     │      30      │     0     │   30  │ Lab protocol
SGI-Reasoning         │      85      │    11     │   96  │ Result interpretation
──────────────────────┼──────────────┼───────────┼───────┼─────────────────────
TOTAL                 │     369      │    38     │  407  │
```

### 2.3 Mapping SGI Tasks to BioMate Functions

| SGI-Bench Task | BioMate Equivalent | Evaluation Focus |
|----------------|-------------------|------------------|
| **Deep Research** | Literature-backed tool selection | Evidence quality, citation accuracy |
| **Idea Generation** | Workflow design proposals | Feasibility, completeness, scientific validity |
| **Dry Experiment** | Code/script generation | Correctness, executability, numerical accuracy |
| **Wet Experiment** | Lab protocol generation | Step ordering, parameter accuracy, safety |
| **Reasoning** | Result interpretation | Logical validity, multimodal understanding |

### 2.4 Development → Production Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DEVELOPMENT PHASE                                 │
│                                                                      │
│  SGI-Bench (407 Simulated Tasks)                                    │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ "Synthetic Users" with expert-curated scientific tasks       │    │
│  │                                                              │    │
│  │  Task: Generate RNA-seq analysis workflow                    │    │
│  │  Domain: Life Science (Genomics)                             │    │
│  │  Expected: Proper QC → Alignment → Quantification → DE       │    │
│  │  Evaluation: Feasibility=?, Correctness=?, Completeness=?    │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              Test Harness Framework                          │    │
│  │              (Developed & Validated)                         │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    PRODUCTION PHASE                                  │
│                                                                      │
│  Real Users (Their Actual Projects)                                 │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │ User: Dr. Smith                                              │    │
│  │ Project: COVID-19 Variant Analysis                           │    │
│  │ Data: 500 patient samples, WGS                               │    │
│  │                                                              │    │
│  │  Task: Analyze my variant calling workflow                   │    │
│  │  Domain: Life Science (Virology/Genomics)                    │    │
│  │  Data: Their actual 500 samples                              │    │
│  │  Evaluation: Same criteria, their specific context           │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                              ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              Same Test Harness Framework                     │    │
│  │              (Now serving real users)                        │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 3: Current State Analysis

### 3.1 Existing Test Harness Components

```
/home/yzhang/biomate/backend/lib/galaxy/ai/test_harness/
├── __init__.py              # Package exports (22 lines)
├── benchmark_suite.py       # Core orchestration (775 lines)
├── metrics_collector.py     # Performance metrics (451 lines)
└── results_analyzer.py      # Statistical analysis (702 lines)

Total: 1,950 lines of well-structured code
```

**Capabilities:**
- ✅ Tool performance benchmarking (runtime, memory, CPU)
- ✅ Quality metrics extraction (alignment rate, variant counts, etc.)
- ✅ Parallel execution support
- ✅ Statistical comparison (t-test, effect size)
- ✅ Report generation (Markdown, HTML, JSON)
- ✅ SQLite persistence

**Gaps:**
- ❌ Per-user/project scoping
- ❌ Scientific quality evaluation (feasibility, correctness)
- ❌ Workflow-level evaluation (beyond individual tools)
- ❌ LLM output quality assessment
- ❌ End-to-end result validation
- ❌ Few-shot template integration

### 3.2 Critical Issues to Fix

| Issue | Location | Severity | Description |
|-------|----------|----------|-------------|
| **Missing Function** | `api/ai_assistant.py:1376` | CRITICAL | `load_benchmark_results()` imported but doesn't exist |
| **Timeout Not Enforced** | `benchmark_suite.py:506` | HIGH | `timeout_seconds` stored but never applied |
| **Resource Leaks** | `BenchmarkResultsDB` | HIGH | No try-finally for database connections |
| **Bare Excepts** | `metrics_collector.py:314,402` | MEDIUM | Silent exception swallowing |
| **No User Scoping** | Throughout | HIGH | All results are global, not per-user |

### 3.3 Related Systems

```
Existing Systems in BioMate:
├── BenchmarkKnowledgeDB (benchmark_knowledge.py)
│   └── Purpose: Published literature benchmarks for tool recommendations
│   └── NOT for user-specific evaluation
│
├── AgenticMemoryService (memory/agentic_memory.py)
│   └── Purpose: User profiles, project context, learning
│   └── Integration point for test harness user/project data
│
├── WorkflowAuditService (services/workflow_audit_service.py)
│   └── Purpose: Track workflow generation history
│   └── Integration point for evaluation triggers
│
└── LLMClient (llm_client.py)
    └── Purpose: Multi-provider LLM access
    └── Used for LLM-based evaluation (judge models)
```

---

## Part 4: Target Architecture

### 4.1 Extended Test Harness Structure

```
/home/yzhang/biomate/backend/lib/galaxy/ai/test_harness/
├── __init__.py                      # Package exports
├── benchmark_suite.py               # Core orchestration (EXTEND)
├── metrics_collector.py             # Performance metrics (EXTEND)
├── results_analyzer.py              # Statistical analysis (EXTEND)
│
├── user_context.py                  # NEW: Per-user/project management
├── scientific_evaluator.py          # NEW: Scientific quality assessment
├── workflow_evaluator.py            # NEW: Workflow-level evaluation
├── sgi_criteria.py                  # NEW: SGI-Bench evaluation criteria
│
├── evaluators/                      # NEW: Task-specific evaluators
│   ├── __init__.py
│   ├── base_evaluator.py           # Abstract base class
│   ├── tool_evaluator.py           # Tool performance (existing logic)
│   ├── workflow_evaluator.py       # Workflow design quality
│   ├── scientific_evaluator.py     # Scientific validity
│   ├── code_evaluator.py           # Code/script quality (Dry Experiment)
│   ├── protocol_evaluator.py       # Lab protocol quality (Wet Experiment)
│   └── reasoning_evaluator.py      # Result interpretation quality
│
├── criteria/                        # NEW: Evaluation criteria from SGI-Bench
│   ├── __init__.py
│   ├── feasibility_criteria.py     # Can it be executed?
│   ├── correctness_criteria.py     # Is it scientifically correct?
│   ├── completeness_criteria.py    # Does it cover all required steps?
│   ├── novelty_criteria.py         # Is it appropriate/innovative?
│   └── rubrics.yaml                # Scoring rubrics
│
├── few_shot/                        # NEW: Expert templates from SGI-Bench
│   ├── __init__.py
│   ├── idea_generation_examples.json
│   ├── code_generation_examples.py
│   ├── protocol_examples.txt
│   └── loader.py                   # Template loading utilities
│
└── persistence/                     # NEW: User-scoped storage
    ├── __init__.py
    ├── user_results_db.py          # Per-user SQLite databases
    └── schemas.py                  # Database schemas
```

### 4.2 Database Schema (Per-User)

```sql
-- Each user gets their own results database
-- Location: /data/users/{user_id}/test_harness/results.db

-- Projects table
CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    domain TEXT,                     -- e.g., "genomics", "proteomics"
    organisms TEXT,                  -- JSON array
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- Datasets within projects
CREATE TABLE datasets (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    name TEXT NOT NULL,
    path TEXT,
    data_type TEXT,                  -- e.g., "RNA-seq", "WGS"
    size_bytes INTEGER,
    sample_count INTEGER,
    metadata JSON,
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

-- Workflows within projects
CREATE TABLE workflows (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    name TEXT,
    workflow_ga JSON,                -- Galaxy workflow definition
    generated_by TEXT,               -- "user", "biomate", "template"
    generation_request TEXT,         -- Original user request
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

-- Evaluation runs
CREATE TABLE evaluation_runs (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    workflow_id TEXT,
    dataset_id TEXT,
    run_type TEXT,                   -- "tool", "workflow", "scientific", "e2e"
    config JSON,                     -- Evaluation configuration
    biomate_version TEXT,            -- Git commit hash
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    status TEXT,                     -- "pending", "running", "complete", "failed"
    FOREIGN KEY (project_id) REFERENCES projects(id),
    FOREIGN KEY (workflow_id) REFERENCES workflows(id),
    FOREIGN KEY (dataset_id) REFERENCES datasets(id)
);

-- Evaluation results (detailed)
CREATE TABLE evaluation_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT NOT NULL,
    evaluation_level TEXT,           -- "tool", "workflow", "scientific", "e2e"
    target_id TEXT,                  -- tool_id, workflow_id, or step_id
    target_name TEXT,

    -- Tool-level metrics
    runtime_seconds REAL,
    peak_memory_gb REAL,
    cpu_utilization REAL,

    -- Workflow-level metrics
    step_count INTEGER,
    connection_validity REAL,        -- 0-1
    parameter_completeness REAL,     -- 0-1

    -- Scientific quality metrics (SGI criteria)
    feasibility_score REAL,          -- 0-100
    correctness_score REAL,          -- 0-100
    completeness_score REAL,         -- 0-100
    novelty_score REAL,              -- 0-100 (for idea generation)
    final_score REAL,                -- Weighted average

    -- Code/Protocol specific
    execution_success BOOLEAN,
    pass_at_1 REAL,
    pass_at_5 REAL,
    sequence_similarity REAL,
    parameter_accuracy REAL,

    -- Reasoning specific
    multi_choice_accuracy REAL,
    reasoning_validity REAL,

    -- Metadata
    details JSON,                    -- Full evaluation details
    evidence_text TEXT,              -- Human-readable explanation
    recommendations JSON,            -- Suggested improvements

    FOREIGN KEY (run_id) REFERENCES evaluation_runs(id)
);

-- LLM judge evaluations (for subjective criteria)
CREATE TABLE judge_evaluations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    result_id INTEGER NOT NULL,
    judge_model TEXT,                -- e.g., "gpt-4", "claude-sonnet"
    dimension TEXT,                  -- "feasibility", "correctness", etc.
    score REAL,
    reasoning TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (result_id) REFERENCES evaluation_results(id)
);

-- Historical tracking for trend analysis
CREATE TABLE evaluation_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id TEXT NOT NULL,
    metric_name TEXT,
    metric_value REAL,
    biomate_version TEXT,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

-- Indexes
CREATE INDEX idx_results_run ON evaluation_results(run_id);
CREATE INDEX idx_results_level ON evaluation_results(evaluation_level);
CREATE INDEX idx_runs_project ON evaluation_runs(project_id);
CREATE INDEX idx_history_project ON evaluation_history(project_id);
CREATE INDEX idx_history_metric ON evaluation_history(metric_name);
```

### 4.3 Core Classes

#### UserTestHarness (Entry Point)

```python
class UserTestHarness:
    """Per-user test harness instance"""

    def __init__(self, user_id: str, project_id: str):
        self.user_id = user_id
        self.project_id = project_id
        self.db = UserResultsDB(user_id)
        self.project = self.db.get_project(project_id)

        # Lazy-loaded evaluators
        self._tool_evaluator = None
        self._workflow_evaluator = None
        self._scientific_evaluator = None

    # === Project Management ===

    def register_dataset(self, dataset: DatasetConfig) -> str:
        """Register a dataset for evaluation"""

    def register_workflow(self, workflow_ga: Dict,
                         generated_by: str = "biomate") -> str:
        """Register a workflow for evaluation"""

    # === Evaluation Methods ===

    def evaluate_tool(self, tool_id: str, dataset_id: str,
                     parameters: Dict = None) -> ToolEvaluationResult:
        """Evaluate a single tool on user's dataset"""

    def evaluate_workflow(self, workflow_id: str,
                         dataset_id: str) -> WorkflowEvaluationResult:
        """Evaluate entire workflow on user's dataset"""

    def evaluate_scientific_quality(self, workflow_id: str,
                                    criteria: List[str] = None) -> ScientificEvaluationResult:
        """Evaluate scientific quality using SGI criteria"""

    def evaluate_end_to_end(self, workflow_id: str,
                           dataset_id: str) -> EndToEndResult:
        """Full evaluation: tools + workflow + scientific + outputs"""

    # === Comparison & Analysis ===

    def compare_workflows(self, workflow_ids: List[str],
                         dataset_id: str) -> ComparisonReport:
        """Compare multiple workflows on same dataset"""

    def compare_configurations(self, workflow_id: str,
                              configs: List[Dict]) -> ComparisonReport:
        """Compare different parameter configurations"""

    def get_history(self, metric: str = None,
                   days: int = 30) -> List[EvaluationHistory]:
        """Get evaluation history for trend analysis"""

    # === Reporting ===

    def generate_report(self, run_id: str,
                       format: str = "markdown") -> str:
        """Generate evaluation report"""

    def export_results(self, run_ids: List[str],
                      format: str = "json") -> str:
        """Export results for external analysis"""
```

#### ScientificEvaluator (SGI Criteria)

```python
class ScientificEvaluator:
    """Evaluates scientific quality using SGI-Bench criteria"""

    def __init__(self, llm_client: LLMClient,
                 criteria_config: Dict = None):
        self.llm = llm_client
        self.criteria = self._load_criteria(criteria_config)
        self.few_shot = FewShotLoader()

    def evaluate(self, workflow: Dict, context: ProjectContext) -> ScientificEvaluationResult:
        """Full scientific evaluation"""

        results = {}

        # Objective evaluations
        results['feasibility'] = self._evaluate_feasibility(workflow, context)
        results['completeness'] = self._evaluate_completeness(workflow, context)
        results['correctness'] = self._evaluate_correctness(workflow, context)

        # Subjective evaluations (LLM judges)
        if self.criteria.use_llm_judges:
            results['judge_scores'] = self._run_llm_evaluation(workflow, context)

        # Aggregate
        results['final_score'] = self._calculate_final_score(results)
        results['recommendations'] = self._generate_recommendations(results)

        return ScientificEvaluationResult(**results)

    def _evaluate_feasibility(self, workflow: Dict,
                             context: ProjectContext) -> FeasibilityResult:
        """Can this workflow actually execute?"""
        checks = {
            'tools_available': self._check_tools_available(workflow),
            'inputs_compatible': self._check_input_compatibility(workflow, context),
            'resources_sufficient': self._check_resource_requirements(workflow, context),
            'dependencies_met': self._check_dependencies(workflow),
        }
        score = sum(checks.values()) / len(checks) * 100
        return FeasibilityResult(score=score, checks=checks)

    def _evaluate_completeness(self, workflow: Dict,
                              context: ProjectContext) -> CompletenessResult:
        """Does workflow cover all required steps for the task?"""
        # Use domain-specific checklists
        required_steps = self._get_required_steps(context.domain, context.task_type)
        present_steps = self._extract_workflow_steps(workflow)

        coverage = len(set(required_steps) & set(present_steps)) / len(required_steps)
        missing = set(required_steps) - set(present_steps)
        extra = set(present_steps) - set(required_steps)

        return CompletenessResult(
            score=coverage * 100,
            missing_steps=list(missing),
            extra_steps=list(extra)
        )

    def _evaluate_correctness(self, workflow: Dict,
                             context: ProjectContext) -> CorrectnessResult:
        """Are parameters and settings scientifically appropriate?"""
        issues = []

        for step in workflow['steps']:
            step_issues = self._check_step_correctness(step, context)
            issues.extend(step_issues)

        score = max(0, 100 - len(issues) * 10)  # Deduct per issue
        return CorrectnessResult(score=score, issues=issues)
```

### 4.4 Evaluation Flow

```
User Request: "Evaluate my RNA-seq workflow"
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     UserTestHarness                                  │
│                                                                      │
│  1. Load user context (project, datasets, preferences)              │
│  2. Load workflow to evaluate                                        │
│  3. Determine evaluation scope                                       │
└────────────────────────────┬────────────────────────────────────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
            ▼                ▼                ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  Tool Evaluator  │ │Workflow Evaluator│ │Scientific Evaluator│
│                  │ │                  │ │                  │
│ - Runtime        │ │ - Step ordering  │ │ - Feasibility    │
│ - Memory         │ │ - Connections    │ │ - Correctness    │
│ - CPU            │ │ - Parameters     │ │ - Completeness   │
│ - Quality metrics│ │ - Data flow      │ │ - LLM judges     │
└────────┬─────────┘ └────────┬─────────┘ └────────┬─────────┘
         │                    │                    │
         └────────────────────┼────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Results Aggregator                               │
│                                                                      │
│  - Combine all evaluation results                                   │
│  - Calculate overall scores                                          │
│  - Generate recommendations                                          │
│  - Store in user's database                                          │
│  - Update history for trend tracking                                 │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Evaluation Report                                │
│                                                                      │
│  Tool Performance:      ████████░░ 80%                              │
│  Workflow Design:       ███████░░░ 70%                              │
│  Scientific Quality:    █████████░ 90%                              │
│  ─────────────────────────────────                                  │
│  Overall Score:         ████████░░ 80%                              │
│                                                                      │
│  Recommendations:                                                    │
│  1. Consider adding QC step before alignment                        │
│  2. Memory allocation may be insufficient for full dataset          │
│  3. Reference genome version should match annotation version        │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: Implementation Plan

### 5.1 Phase 0: Fix Critical Issues (Pre-requisite)

**Duration**: 1-2 days
**Priority**: CRITICAL

| Task | File | Description |
|------|------|-------------|
| 5.0.1 | `test_harness/__init__.py` | Implement `load_benchmark_results()` function |
| 5.0.2 | `benchmark_suite.py` | Add timeout enforcement to executor |
| 5.0.3 | `benchmark_suite.py` | Wrap database operations in context managers |
| 5.0.4 | `metrics_collector.py` | Replace bare excepts with proper error handling |
| 5.0.5 | `benchmark_knowledge.py` | Add connection timeout and context managers |

**Deliverables**:
- All critical issues resolved
- Existing functionality preserved
- Unit tests for fixes

### 5.2 Phase 1: User Context Infrastructure

**Duration**: 3-4 days
**Priority**: HIGH

| Task | Description |
|------|-------------|
| 5.1.1 | Create `user_context.py` with `UserTestHarness` class |
| 5.1.2 | Create `persistence/user_results_db.py` with per-user SQLite |
| 5.1.3 | Create `persistence/schemas.py` with database schema |
| 5.1.4 | Integrate with existing `AgenticMemoryService` for user/project data |
| 5.1.5 | Add project and dataset registration methods |
| 5.1.6 | Add workflow registration and tracking |

**Deliverables**:
- Per-user test harness instances
- User-scoped database storage
- Integration with BioMate's user/project models

### 5.3 Phase 2: SGI-Bench Criteria Integration

**Duration**: 4-5 days
**Priority**: HIGH

| Task | Description |
|------|-------------|
| 5.2.1 | Extract few-shot examples from SGI-Bench datasets |
| 5.2.2 | Create `criteria/` directory with evaluation rubrics |
| 5.2.3 | Implement `FeasibilityCriteria` class |
| 5.2.4 | Implement `CorrectnessCriteria` class |
| 5.2.5 | Implement `CompletenessCriteria` class |
| 5.2.6 | Create `sgi_criteria.py` unified interface |
| 5.2.7 | Implement LLM judge evaluation (multi-judge voting) |

**Deliverables**:
- SGI-Bench evaluation criteria as reusable modules
- Few-shot template library
- LLM-based subjective evaluation

### 5.4 Phase 3: Evaluator Implementation

**Duration**: 5-7 days
**Priority**: HIGH

| Task | Description |
|------|-------------|
| 5.3.1 | Create `evaluators/base_evaluator.py` abstract class |
| 5.3.2 | Refactor existing tool evaluation into `tool_evaluator.py` |
| 5.3.3 | Implement `workflow_evaluator.py` |
| 5.3.4 | Implement `scientific_evaluator.py` |
| 5.3.5 | Implement `code_evaluator.py` (Dry Experiment style) |
| 5.3.6 | Implement `protocol_evaluator.py` (Wet Experiment style) |
| 5.3.7 | Implement `reasoning_evaluator.py` |

**Deliverables**:
- Complete evaluator suite
- Consistent interface across all evaluators
- SGI-Bench compatible evaluation

### 5.5 Phase 4: Validation with SGI-Bench

**Duration**: 3-4 days
**Priority**: HIGH

| Task | Description |
|------|-------------|
| 5.4.1 | Create SGI-Bench simulation runner |
| 5.4.2 | Run Life Science samples (369) through test harness |
| 5.4.3 | Run Chemistry samples (38) through test harness |
| 5.4.4 | Compare results with published SGI-Bench scores |
| 5.4.5 | Identify and fix discrepancies |
| 5.4.6 | Document validation results |

**Deliverables**:
- Validated test harness against SGI-Bench
- Performance baselines established
- Discrepancy analysis report

### 5.6 Phase 5: Frontend Integration

**Duration**: 4-5 days
**Priority**: MEDIUM

| Task | Description |
|------|-------------|
| 5.5.1 | Create test harness API endpoints |
| 5.5.2 | Create test harness dashboard component |
| 5.5.3 | Add evaluation trigger to workflow artifact UI |
| 5.5.4 | Create results visualization components |
| 5.5.5 | Add historical trend charts |
| 5.5.6 | Implement evaluation report viewer |

**Deliverables**:
- Complete frontend UI for test harness
- Integration with existing workflow UI
- Real-time evaluation progress

### 5.7 Phase 6: Documentation & Polish

**Duration**: 2-3 days
**Priority**: MEDIUM

| Task | Description |
|------|-------------|
| 5.6.1 | Write user documentation |
| 5.6.2 | Write API documentation |
| 5.6.3 | Create example notebooks |
| 5.6.4 | Add inline code documentation |
| 5.6.5 | Performance optimization |
| 5.6.6 | Final testing and bug fixes |

**Deliverables**:
- Complete documentation
- Example usage notebooks
- Production-ready code

---

## Part 6: SGI-Bench Few-Shot Templates

### 6.1 Idea Generation Template

Extract from SGI-Bench for BioMate's workflow generation:

```json
{
  "template_type": "idea_generation",
  "domain": "life_science",
  "example": {
    "Idea": "We propose an integrated multi-omics analysis framework that combines RNA-seq differential expression with proteomics validation...",
    "ImplementationSteps": {
      "1": "Data preprocessing: Quality control of raw sequencing reads using FastQC, adapter trimming with Trimmomatic",
      "2": "Alignment: Map reads to reference genome using STAR aligner with default parameters for the target organism",
      "3": "Quantification: Generate gene-level counts using featureCounts with strand-specific settings",
      "4": "Normalization: Apply TMM normalization to account for library size differences",
      "5": "Differential expression: Use DESeq2 with batch correction for confounding variables",
      "6": "Validation: Cross-reference with proteomics data using correlation analysis"
    },
    "ImplementationOrder": ["1-2", "2-3", "3-4", "4-5", "5-6"],
    "Dataset": "RNA-seq from 50 patient samples (25 treatment, 25 control), paired-end 150bp, ~30M reads per sample",
    "EvaluationMetrics": {
      "Alignment Rate": "Target >85% uniquely mapped reads",
      "Reproducibility": "Pearson correlation >0.95 between biological replicates",
      "Validation": "Protein-mRNA correlation >0.6 for significantly changed genes"
    },
    "ExpectedOutcome": "Identify 200-500 differentially expressed genes (FDR<0.05, |log2FC|>1) with >70% validation rate in proteomics"
  }
}
```

### 6.2 Evaluation Rubrics

```yaml
# criteria/rubrics.yaml

feasibility:
  description: "Can the workflow be executed with available resources?"
  components:
    tools_available:
      weight: 0.3
      scoring:
        1.0: "All tools available in Galaxy/BioMate"
        0.5: "Most tools available, some require installation"
        0.0: "Critical tools unavailable"

    inputs_compatible:
      weight: 0.3
      scoring:
        1.0: "All inputs match expected formats"
        0.5: "Minor format conversions needed"
        0.0: "Major incompatibilities"

    resources_sufficient:
      weight: 0.2
      scoring:
        1.0: "Resources well within capacity"
        0.5: "Resources at limit but feasible"
        0.0: "Insufficient resources"

    dependencies_met:
      weight: 0.2
      scoring:
        1.0: "All dependencies satisfied"
        0.5: "Some dependencies need attention"
        0.0: "Critical dependencies missing"

correctness:
  description: "Are parameters and settings scientifically appropriate?"
  components:
    parameter_validity:
      weight: 0.4
      examples:
        correct: "STAR --sjdbOverhang 149 for 150bp reads"
        incorrect: "STAR --sjdbOverhang 50 for 150bp reads"

    organism_match:
      weight: 0.3
      examples:
        correct: "Using GRCh38 for human samples"
        incorrect: "Using mm10 for human samples"

    method_appropriateness:
      weight: 0.3
      examples:
        correct: "DESeq2 for count data with replicates"
        incorrect: "t-test on raw counts without normalization"

completeness:
  description: "Does the workflow include all necessary steps?"
  components:
    required_steps:
      rna_seq:
        - "quality_control"
        - "trimming"
        - "alignment"
        - "quantification"
        - "normalization"
        - "differential_expression"

      variant_calling:
        - "quality_control"
        - "alignment"
        - "duplicate_marking"
        - "base_recalibration"
        - "variant_calling"
        - "variant_filtering"
        - "annotation"
```

---

## Part 7: Success Metrics

### 7.1 Development Success

| Metric | Target | Measurement |
|--------|--------|-------------|
| SGI-Bench Validation | >90% samples evaluated | Count of successful evaluations |
| Score Correlation | >0.8 with published | Pearson correlation of scores |
| Evaluation Latency | <30s per workflow | Average evaluation time |
| Database Reliability | 0 data loss | Automated recovery tests |

### 7.2 Production Success

| Metric | Target | Measurement |
|--------|--------|-------------|
| User Adoption | >50% of active users | Users with test harness activity |
| Evaluation Frequency | >2 per project/week | Average evaluations per project |
| Issue Detection | >80% pre-execution | Issues found by evaluation vs. runtime |
| User Satisfaction | >4/5 rating | User feedback surveys |

### 7.3 Scientific Quality

| Metric | Target | Measurement |
|--------|--------|-------------|
| Feasibility Accuracy | >90% | Workflows that execute successfully |
| Correctness Accuracy | >85% | Expert validation of assessments |
| Recommendation Utility | >70% applied | Recommendations users implement |

---

## Part 8: Risk Analysis

### 8.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| LLM judge inconsistency | Medium | Medium | Multi-judge voting, calibration |
| Performance bottleneck | Medium | High | Async evaluation, caching |
| Database growth | High | Medium | Retention policies, archiving |
| Integration complexity | Medium | High | Phased rollout, feature flags |

### 8.2 Scientific Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Domain coverage gaps | Medium | Medium | Extensible criteria framework |
| Criteria drift | Low | High | Version-controlled rubrics |
| False confidence | Medium | High | Uncertainty quantification |

---

## Part 9: Timeline Summary

```
Week 1:  Phase 0 (Critical Fixes) + Phase 1 Start (User Context)
Week 2:  Phase 1 Complete + Phase 2 Start (SGI Criteria)
Week 3:  Phase 2 Complete + Phase 3 Start (Evaluators)
Week 4:  Phase 3 Complete
Week 5:  Phase 4 (SGI-Bench Validation)
Week 6:  Phase 5 (Frontend Integration)
Week 7:  Phase 6 (Documentation) + Final Testing

Total: ~7 weeks for full implementation
MVP (Phases 0-3): ~4 weeks
```

---

## Part 10: Open Questions

1. **Evaluation Triggers**: Should evaluation run automatically on workflow generation, or only on user request?

2. **Resource Allocation**: How much compute to allocate for LLM judge evaluations?

3. **Historical Retention**: How long to retain evaluation history per user?

4. **Sharing**: Should users be able to share evaluation results/configurations?

5. **Feedback Loop**: How to incorporate evaluation results back into workflow generation improvement?

---

## Appendix A: File Locations

```
SGI-Bench Datasets:
/home/yzhang/biomate/research/benchmark_evaluation/sgi_bench_datasets/

SGI-Bench Repository:
/home/yzhang/biomate/research/benchmark_evaluation/SGI-Bench/

Existing Test Harness:
/home/yzhang/biomate/backend/lib/galaxy/ai/test_harness/

Benchmark Knowledge:
/home/yzhang/biomate/backend/lib/galaxy/ai/benchmark_knowledge.py

AI Assistant:
/home/yzhang/biomate/backend/lib/galaxy/ai/ai_assistant.py

Frontend Components:
/home/yzhang/biomate/frontend/client/src/components/
```

## Appendix B: Related Documents

- `SGI_BENCH_EVALUATION_ISSUES_SUMMARY.md` - Issues found in LLM evaluation
- `SGI_BENCH_BIOMATE_INTEGRATION_PLAN.md` - Initial integration plan (superseded by this document)
- SGI-Bench Paper: https://arxiv.org/pdf/2512.16969

---

**Document End**
