# BioMate Enhancement Plan: Citations, Parameter Tuning & Test Harness

**Date:** 2025-12-19
**Status:** Planning
**Author:** AI Assistant

## Executive Summary

This document outlines three interconnected enhancements to BioMate:
1. **Citation & Best Practices Integration** - Embed scientific citations and parameter recommendations into workflow generation
2. **Progressive Parameter Tuning** - Small data first, then scale approach with user controls
3. **Performance Test Harness** - Systematic comparison of methods, parameters, and datasets

---

## Part 1: Citation & Best Practices Integration

### 1.1 Information Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           USER REQUEST                                       │
│                    "Analyze my RNA-seq data"                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AIAssistant.process_request()                        │
│  /lib/galaxy/ai/ai_assistant.py                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ 1. Parse intent → "RNA-seq differential expression"                  │   │
│  │ 2. Query tool_knowledge table for relevant tools                     │   │
│  │ 3. Retrieve citations + best practices for each tool                 │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ToolKnowledgeProvider (NEW)                               │
│  /lib/galaxy/ai/tool_knowledge_provider.py                                  │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ get_tool_knowledge(tool_id) → {                                      │   │
│  │   "citation": {"doi": "10.1038/...", "title": "...", "year": 2021}, │   │
│  │   "recommended_params": {"threads": "8-16", "memory": "32GB"},      │   │
│  │   "use_cases": ["RNA-seq alignment", "fusion detection"],           │   │
│  │   "limitations": ["High memory for human genome"],                  │   │
│  │   "alternatives": ["HISAT2", "Salmon"]                              │   │
│  │ }                                                                    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                   GalaxyWorkflowGenerator                                    │
│  /lib/galaxy/ai/galaxy_workflow_generator.py                                │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ _build_step_with_knowledge():                                        │   │
│  │   - Inject citation into step annotation                            │   │
│  │   - Apply recommended_params as defaults                            │   │
│  │   - Add limitations as warnings                                     │   │
│  │   - Include confidence score based on citation quality              │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WORKFLOW OUTPUT                                      │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ Step 1: STAR Aligner                                                 │   │
│  │   Citation: Dobin et al. 2013, doi:10.1093/bioinformatics/bts635    │   │
│  │   Parameters: --runThreadN 16, --outSAMtype BAM SortedByCoordinate  │   │
│  │   Confidence: 0.95 (peer-reviewed best practice)                    │   │
│  │   Warning: Requires ~30GB RAM for human genome                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ Step 2: DESeq2                                                       │   │
│  │   Citation: Love et al. 2014, doi:10.1186/s13059-014-0550-8         │   │
│  │   Parameters: lfcThreshold=0, alpha=0.05                            │   │
│  │   Confidence: 0.92 (gold standard for DE analysis)                  │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Implementation Components

#### A. ToolKnowledgeProvider (NEW)
**File:** `/lib/galaxy/ai/tool_knowledge_provider.py`

```python
class ToolKnowledgeProvider:
    """Provides citations and best practices for tools."""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self._cache = {}  # LRU cache for frequently accessed tools

    def get_tool_knowledge(self, tool_id: str) -> Optional[ToolKnowledge]:
        """Retrieve citation + best practices for a tool."""

    def get_recommended_parameters(self, tool_id: str, context: Dict) -> Dict:
        """Get context-aware parameter recommendations."""

    def format_citation(self, tool_id: str, style: str = "apa") -> str:
        """Format citation for display (APA, MLA, BibTeX)."""

    def get_parameter_confidence(self, tool_id: str, param: str, value: Any) -> float:
        """Score parameter value against best practices."""
```

#### B. Enhanced Workflow Step Annotation
**File:** `/lib/galaxy/ai/galaxy_workflow_generator.py`

Modify `_build_step_annotation()` to include:
```python
def _build_step_annotation(self, tool_id: str, tool_name: str) -> str:
    knowledge = self.knowledge_provider.get_tool_knowledge(tool_id)

    annotation = f"Tool: {tool_name}\n"

    if knowledge and knowledge.citation:
        citation = knowledge.citation
        annotation += f"\nCitation: {citation.authors[0]} et al. ({citation.year})"
        annotation += f"\nDOI: {citation.doi}"
        annotation += f"\nPMID: {citation.pmid}" if citation.pmid else ""

    if knowledge and knowledge.limitations:
        annotation += f"\n\nLimitations:\n"
        for limit in knowledge.limitations:
            annotation += f"  - {limit}\n"

    return annotation
```

#### C. API Response Enhancement
**File:** `/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

```python
class AIWorkflowResponse(BaseModel):
    workflow: Dict[str, Any]
    citations: List[Citation]  # NEW
    parameter_recommendations: Dict[str, ParameterRecommendation]  # NEW
    confidence_scores: Dict[str, float]  # NEW
    methods_section: str  # NEW - Auto-generated methods text
```

#### D. Methods Section Generator (NEW)
**File:** `/lib/galaxy/ai/methods_generator.py`

Auto-generate publication-ready methods section:
```python
class MethodsSectionGenerator:
    def generate(self, workflow: Dict, citations: List[Citation]) -> str:
        """Generate methods section text with proper citations."""
        # Example output:
        # "Reads were aligned to the human reference genome (GRCh38) using
        #  STAR v2.7.10 (Dobin et al., 2013) with default parameters..."
```

### 1.3 Database Schema Enhancement

```sql
-- Add confidence scoring to tool_knowledge
ALTER TABLE tool_knowledge ADD COLUMN citation_quality_score FLOAT DEFAULT 0.5;
ALTER TABLE tool_knowledge ADD COLUMN parameter_confidence_source TEXT;  -- 'benchmark', 'protocol', 'manual'

-- Track parameter usage success
CREATE TABLE parameter_usage_history (
    id INTEGER PRIMARY KEY,
    tool_id TEXT NOT NULL,
    parameter_name TEXT NOT NULL,
    parameter_value TEXT,
    execution_success BOOLEAN,
    execution_time_seconds FLOAT,
    user_satisfaction INTEGER,  -- 1-5 rating if provided
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

## Part 2: Progressive Parameter Tuning (Small Data First)

### 2.1 Rationale

Using a small portion of data for parameter tuning before full analysis is a **well-established best practice** in bioinformatics:

| Benefit | Description |
|---------|-------------|
| **Fast iteration** | 10% of data runs 10x faster, enabling rapid parameter exploration |
| **Cost savings** | Reduce compute costs during optimization phase |
| **Early error detection** | Catch configuration issues before committing hours of compute |
| **Representative sampling** | Stratified sampling ensures subset represents full dataset |
| **User confidence** | Preview results before committing to full analysis |

### 2.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      USER WORKFLOW REQUEST                                   │
│              "Run DESeq2 on my 100 sample RNA-seq dataset"                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ProgressiveTuningController (NEW)                         │
│  /lib/galaxy/ai/progressive_tuning.py                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ Phase 1: PILOT RUN (default 10% of data)                            │   │
│  │   - Stratified sampling to preserve group balance                   │   │
│  │   - Run with recommended default parameters                         │   │
│  │   - Collect metrics: runtime, memory, output quality                │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ Phase 2: PARAMETER OPTIMIZATION (optional)                          │   │
│  │   - Compare parameter sets on pilot data                            │   │
│  │   - Grid search or Bayesian optimization                            │   │
│  │   - Report: "threads=16 completed 2x faster than threads=8"         │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ Phase 3: USER REVIEW                                                 │   │
│  │   - Present pilot results + parameter recommendations               │   │
│  │   - User approves/modifies parameters                               │   │
│  │   - Estimate full run time/cost                                     │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                    │                                         │
│                                    ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ Phase 4: FULL RUN                                                    │   │
│  │   - Execute with optimized parameters on full dataset               │   │
│  │   - Apply learned settings from pilot phase                         │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Implementation Components

#### A. ProgressiveTuningController (NEW)
**File:** `/lib/galaxy/ai/progressive_tuning.py`

```python
@dataclass
class TuningConfig:
    pilot_fraction: float = 0.1  # 10% of data for pilot
    min_pilot_samples: int = 3   # Minimum samples even for small datasets
    max_pilot_samples: int = 50  # Cap for very large datasets
    sampling_strategy: str = "stratified"  # 'random', 'stratified', 'first_n'
    auto_optimize: bool = False  # Auto-run parameter optimization
    optimization_budget: int = 5  # Max parameter combinations to try

class ProgressiveTuningController:
    def create_pilot_subset(self, dataset: Dataset, config: TuningConfig) -> Dataset:
        """Create representative subset for pilot run."""

    def run_pilot(self, workflow: Workflow, pilot_data: Dataset) -> PilotResult:
        """Execute workflow on pilot subset, collect metrics."""

    def optimize_parameters(self, workflow: Workflow, pilot_data: Dataset,
                          param_space: Dict) -> OptimizationResult:
        """Search for optimal parameters on pilot data."""

    def estimate_full_run(self, pilot_result: PilotResult, full_size: int) -> Estimate:
        """Extrapolate runtime/memory for full dataset."""

    def execute_full_run(self, workflow: Workflow, full_data: Dataset,
                        optimized_params: Dict) -> ExecutionResult:
        """Run full analysis with optimized parameters."""
```

#### B. Sampling Strategies
**File:** `/lib/galaxy/ai/sampling.py`

```python
class DataSampler:
    @staticmethod
    def stratified_sample(dataset: Dataset, fraction: float,
                         strata_column: str) -> Dataset:
        """Preserve group proportions (e.g., treatment vs control)."""

    @staticmethod
    def random_sample(dataset: Dataset, fraction: float, seed: int = 42) -> Dataset:
        """Simple random sampling."""

    @staticmethod
    def representative_sample(dataset: Dataset, fraction: float) -> Dataset:
        """Select samples that maximize diversity (k-medoids)."""
```

#### C. UI/API Integration

**New API Endpoints:**
```python
# /api/workflows/{id}/pilot
POST /api/workflows/{workflow_id}/pilot
{
    "dataset_id": "abc123",
    "pilot_config": {
        "fraction": 0.1,
        "strategy": "stratified",
        "strata_column": "condition"
    }
}

# Response
{
    "pilot_job_id": "pilot_xyz",
    "estimated_time": "5 minutes",
    "samples_selected": 10,
    "sampling_report": {...}
}

# /api/workflows/{id}/pilot/{pilot_id}/results
GET /api/workflows/{workflow_id}/pilot/{pilot_id}/results
{
    "status": "complete",
    "metrics": {
        "runtime_seconds": 312,
        "peak_memory_gb": 8.2,
        "output_files": 4
    },
    "parameter_recommendations": {...},
    "full_run_estimate": {
        "estimated_runtime": "52 minutes",
        "estimated_cost": "$0.85"
    }
}

# /api/workflows/{id}/execute
POST /api/workflows/{workflow_id}/execute
{
    "dataset_id": "abc123",
    "use_pilot_params": true,
    "pilot_id": "pilot_xyz"
}
```

#### D. Frontend Integration

Add to chat interface:
```
┌─────────────────────────────────────────────────────────────────┐
│ BioMate suggests running a pilot test first:                    │
│                                                                  │
│ Your dataset has 100 samples. Running a pilot on 10 samples     │
│ will take ~5 minutes and help optimize parameters.              │
│                                                                  │
│ [Run Pilot First (Recommended)]  [Run Full Analysis]  [Configure]│
└─────────────────────────────────────────────────────────────────┘
```

### 2.4 Configuration Storage

**File:** `/lib/galaxy/config/progressive_tuning_defaults.yml`

```yaml
progressive_tuning:
  enabled: true
  default_pilot_fraction: 0.1
  min_pilot_samples: 3
  max_pilot_samples: 50

  # Per-workflow-type overrides
  workflow_overrides:
    rna_seq_de:
      pilot_fraction: 0.15
      min_pilot_samples: 6  # Need enough for statistical power

    variant_calling:
      pilot_fraction: 0.05
      sampling_strategy: "chromosome"  # Sample by chromosome

    metagenomics:
      pilot_fraction: 0.1
      sampling_strategy: "random"

  # Auto-optimization settings
  optimization:
    enabled: false  # Opt-in
    max_iterations: 10
    early_stopping: true
    metric: "runtime"  # 'runtime', 'memory', 'quality'
```

---

## Part 3: Performance Test Harness

### 3.1 Purpose

Build a systematic framework to compare:
- **Methods**: STAR vs HISAT2 vs Salmon for RNA-seq alignment
- **Parameters**: Different thread counts, memory settings, quality thresholds
- **Datasets**: Different species, sequencing depths, data qualities

### 3.2 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BioMate Test Harness                                 │
│  /lib/galaxy/ai/test_harness/                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │  BenchmarkSuite │  │ ComparisonRunner│  │  MetricsCollector│            │
│  │                 │  │                 │  │                 │             │
│  │ - Define tests  │  │ - Execute runs  │  │ - Timing        │             │
│  │ - Load datasets │  │ - Track state   │  │ - Memory        │             │
│  │ - Configure     │  │ - Handle errors │  │ - Quality       │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           │                    │                    │                       │
│           └────────────────────┼────────────────────┘                       │
│                                ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        ResultsAnalyzer                               │   │
│  │  - Statistical comparison (paired t-test, Wilcoxon)                  │   │
│  │  - Visualization (runtime plots, memory profiles)                    │   │
│  │  - Report generation (HTML, JSON, Markdown)                          │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                │                                            │
│                                ▼                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        Results Storage                               │   │
│  │  /database/benchmark_results.db                                      │   │
│  │  - Historical comparisons                                            │   │
│  │  - Trend analysis                                                    │   │
│  │  - Regression detection                                              │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Implementation Components

#### A. BenchmarkSuite
**File:** `/lib/galaxy/ai/test_harness/benchmark_suite.py`

```python
@dataclass
class BenchmarkScenario:
    name: str
    description: str
    tools: List[str]  # Tools to compare
    parameter_sets: List[Dict[str, Any]]  # Parameter combinations
    datasets: List[str]  # Dataset IDs or paths
    metrics: List[str]  # ['runtime', 'memory', 'accuracy', 'output_size']
    repetitions: int = 3  # For statistical significance
    timeout_seconds: int = 3600

class BenchmarkSuite:
    def __init__(self, config_path: str):
        self.scenarios = self._load_scenarios(config_path)
        self.results_db = BenchmarkResultsDB()

    def add_scenario(self, scenario: BenchmarkScenario):
        """Register a benchmark scenario."""

    def run_all(self, parallel: bool = False) -> BenchmarkResults:
        """Execute all registered scenarios."""

    def run_scenario(self, name: str) -> ScenarioResult:
        """Execute a single scenario."""

    def compare(self, scenario_name: str) -> ComparisonReport:
        """Generate comparison report for a scenario."""
```

#### B. Benchmark Configuration Example
**File:** `/lib/galaxy/ai/test_harness/benchmarks/rna_seq_aligners.yml`

```yaml
name: "RNA-seq Aligner Comparison"
description: "Compare STAR, HISAT2, and Salmon for RNA-seq alignment"

tools:
  - id: "star"
    name: "STAR"
    versions: ["2.7.10", "2.7.11"]

  - id: "hisat2"
    name: "HISAT2"
    versions: ["2.2.1"]

  - id: "salmon"
    name: "Salmon"
    versions: ["1.10.0"]

parameter_sets:
  - name: "low_threads"
    params:
      threads: 4
      memory_gb: 16

  - name: "high_threads"
    params:
      threads: 16
      memory_gb: 32

  - name: "max_performance"
    params:
      threads: 32
      memory_gb: 64

datasets:
  - name: "human_small"
    path: "/test_data/human_rnaseq_10k_reads.fastq"
    species: "human"
    read_count: 10000

  - name: "human_medium"
    path: "/test_data/human_rnaseq_1M_reads.fastq"
    species: "human"
    read_count: 1000000

  - name: "mouse_small"
    path: "/test_data/mouse_rnaseq_10k_reads.fastq"
    species: "mouse"
    read_count: 10000

metrics:
  - runtime_seconds
  - peak_memory_gb
  - alignment_rate
  - multi_mapping_rate
  - output_size_mb

evaluation:
  primary_metric: "alignment_rate"
  secondary_metrics: ["runtime_seconds", "peak_memory_gb"]
  statistical_test: "paired_ttest"
  significance_level: 0.05

repetitions: 3
timeout_seconds: 7200
```

#### C. MetricsCollector
**File:** `/lib/galaxy/ai/test_harness/metrics_collector.py`

```python
class MetricsCollector:
    """Collect performance and quality metrics during benchmark runs."""

    def collect_runtime(self, job_id: str) -> float:
        """Get job runtime in seconds."""

    def collect_memory(self, job_id: str) -> MemoryProfile:
        """Get peak and average memory usage."""

    def collect_output_quality(self, output_path: str,
                               ground_truth: Optional[str] = None) -> QualityMetrics:
        """Assess output quality (alignment rate, error rate, etc.)."""

    def collect_resource_usage(self, job_id: str) -> ResourceUsage:
        """CPU, I/O, network usage during execution."""
```

#### D. ResultsAnalyzer
**File:** `/lib/galaxy/ai/test_harness/results_analyzer.py`

```python
class ResultsAnalyzer:
    def statistical_comparison(self, results: BenchmarkResults,
                               metric: str) -> StatisticalResult:
        """Compare methods using appropriate statistical tests."""
        # Returns: p-values, effect sizes, confidence intervals

    def generate_plots(self, results: BenchmarkResults) -> List[Path]:
        """Generate visualization plots."""
        # - Bar charts comparing methods
        # - Box plots showing variability
        # - Scatter plots for parameter sensitivity
        # - Memory/runtime profiles over time

    def generate_report(self, results: BenchmarkResults,
                       format: str = "html") -> str:
        """Generate comprehensive benchmark report."""

    def detect_regression(self, current: BenchmarkResults,
                         baseline: BenchmarkResults) -> RegressionReport:
        """Compare against baseline to detect performance regressions."""
```

#### E. Results Database Schema
**File:** `/database/benchmark_results.db`

```sql
CREATE TABLE benchmark_runs (
    id INTEGER PRIMARY KEY,
    scenario_name TEXT NOT NULL,
    run_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    git_commit TEXT,
    environment_hash TEXT,
    status TEXT,  -- 'running', 'complete', 'failed'
    summary JSON
);

CREATE TABLE benchmark_results (
    id INTEGER PRIMARY KEY,
    run_id INTEGER REFERENCES benchmark_runs(id),
    tool_id TEXT NOT NULL,
    tool_version TEXT,
    parameter_set TEXT,
    dataset_name TEXT,
    repetition INTEGER,

    -- Metrics
    runtime_seconds FLOAT,
    peak_memory_gb FLOAT,
    cpu_utilization FLOAT,

    -- Quality metrics (tool-specific)
    quality_metrics JSON,

    -- Outputs
    output_size_mb FLOAT,
    output_file_count INTEGER,

    -- Status
    success BOOLEAN,
    error_message TEXT
);

CREATE TABLE comparison_reports (
    id INTEGER PRIMARY KEY,
    run_id INTEGER REFERENCES benchmark_runs(id),
    report_type TEXT,  -- 'html', 'json', 'markdown'
    report_path TEXT,
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 3.4 CLI Interface

**File:** `/scripts/run_benchmarks.py`

```bash
# Run all benchmarks
python scripts/run_benchmarks.py --all

# Run specific scenario
python scripts/run_benchmarks.py --scenario rna_seq_aligners

# Run with specific datasets only
python scripts/run_benchmarks.py --scenario rna_seq_aligners --datasets human_small,human_medium

# Compare against baseline
python scripts/run_benchmarks.py --scenario rna_seq_aligners --compare-baseline run_123

# Generate report only (from existing results)
python scripts/run_benchmarks.py --report run_456 --format html

# List available scenarios
python scripts/run_benchmarks.py --list-scenarios
```

### 3.5 Integration with CI/CD

**File:** `.github/workflows/benchmark.yml`

```yaml
name: Performance Benchmarks

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 2 * * 0'  # Weekly Sunday 2am

jobs:
  benchmark:
    runs-on: self-hosted  # Need consistent hardware
    steps:
      - uses: actions/checkout@v3

      - name: Run benchmarks
        run: python scripts/run_benchmarks.py --all --output results/

      - name: Check for regressions
        run: python scripts/run_benchmarks.py --check-regression --threshold 10%

      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: benchmark-results
          path: results/
```

---

## Part 4: Implementation Phases

### Phase 1: Foundation
- [ ] Create `ToolKnowledgeProvider` class
- [ ] Modify `GalaxyWorkflowGenerator` to inject citations
- [ ] Add citation fields to API response models
- [ ] Create basic pilot run infrastructure

### Phase 2: Progressive Tuning
- [ ] Implement `ProgressiveTuningController`
- [ ] Add sampling strategies
- [ ] Create pilot run API endpoints
- [ ] Frontend pilot run UI integration

### Phase 3: Test Harness Core
- [ ] Implement `BenchmarkSuite` framework
- [ ] Create `MetricsCollector`
- [ ] Set up benchmark results database
- [ ] Create initial benchmark scenarios (RNA-seq aligners)

### Phase 4: Analysis & Reporting
- [ ] Implement `ResultsAnalyzer`
- [ ] Create visualization components
- [ ] Build report generation (HTML, Markdown)
- [ ] Add regression detection

### Phase 5: Integration & Polish
- [ ] CI/CD integration
- [ ] Documentation
- [ ] Additional benchmark scenarios
- [ ] Performance optimization

---

## Key Files to Create/Modify

### New Files
| File | Purpose |
|------|---------|
| `/lib/galaxy/ai/tool_knowledge_provider.py` | Citation & best practices provider |
| `/lib/galaxy/ai/methods_generator.py` | Auto-generate methods sections |
| `/lib/galaxy/ai/progressive_tuning.py` | Pilot run controller |
| `/lib/galaxy/ai/sampling.py` | Data sampling strategies |
| `/lib/galaxy/ai/test_harness/benchmark_suite.py` | Benchmark framework |
| `/lib/galaxy/ai/test_harness/metrics_collector.py` | Metrics collection |
| `/lib/galaxy/ai/test_harness/results_analyzer.py` | Analysis & reporting |
| `/config/progressive_tuning_defaults.yml` | Tuning configuration |
| `/scripts/run_benchmarks.py` | CLI for benchmarks |

### Files to Modify
| File | Changes |
|------|---------|
| `/lib/galaxy/ai/ai_assistant.py` | Integrate knowledge provider |
| `/lib/galaxy/ai/galaxy_workflow_generator.py` | Add citation injection |
| `/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Enhanced response models |
| `/lib/galaxy/webapps/galaxy/api/workflows.py` | Pilot run endpoints |

---

## Summary

This plan provides a comprehensive approach to:

1. **Citation Integration**: Embed scientific credibility into every workflow step
2. **Progressive Tuning**: Enable smart parameter optimization with minimal compute waste
3. **Test Harness**: Systematic benchmarking for continuous quality improvement

The three systems are interconnected:
- Citations inform **default parameters** in workflows
- Progressive tuning **validates** those defaults on real data
- Test harness **measures** parameter effectiveness across scenarios
- Results feed back to **improve** citation-based recommendations

This creates a virtuous cycle of evidence-based bioinformatics workflow generation.
