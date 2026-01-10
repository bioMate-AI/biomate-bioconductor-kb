# SGI-Bench + BioMate Test Harness Integration Plan

**Date**: 2025-12-30
**Objective**: Repeat SGI-Bench evaluation for Life Science & Chemistry domains using BioMate's test harness

---

## Executive Summary

This plan integrates SGI-Bench (Scientific General Intelligence benchmark) with BioMate's existing test harness to:
1. Evaluate LLM performance on Life Science (369 samples) and Chemistry (38 samples) domains
2. Track performance across different LLM versions
3. Record BioMate modifications and their impact on evaluation results

---

## Part 1: Key Findings from Exploration

### 1.1 SGI-Bench Few-Shot Learning Configuration

| Task | Approach | Example Format |
|------|----------|----------------|
| **Task 1: Deep Research** | Zero-shot | `<answer>` XML tags |
| **Task 2: Idea Generation** | One-shot | Full JSON example with 6 required fields |
| **Task 3.1: Dry Experiment** | Few-shot | Code block examples in `<answer>` tags |
| **Task 3.2: Wet Experiment** | Few-shot | Protocol format `<Action>(params)` |
| **Task 4: Reasoning** | Zero-shot | System prompt + `\boxed{A}` format |

### 1.2 Life Science & Chemistry Sample Distribution

```
Dataset               | Life Science | Chemistry | Total Target
----------------------|--------------|-----------|-------------
SGI-DeepResearch      |     87       |    11     |    98
SGI-IdeaGeneration    |     87       |    11     |    98
SGI-DryExperiment     |     80       |     5     |    85
SGI-WetExperiment     |     30       |     0     |    30
SGI-Reasoning         |     85       |    11     |    96
----------------------|--------------|-----------|-------------
TOTAL                 |    369       |    38     |   407
```

### 1.3 BioMate Test Harness Components

```
/home/yzhang/biomate/backend/lib/galaxy/ai/test_harness/
├── benchmark_suite.py      # Orchestration (BenchmarkSuite class)
├── metrics_collector.py    # Performance measurement
├── results_analyzer.py     # Statistical analysis & reporting
└── benchmark_knowledge.py  # Literature knowledge DB
```

**Key Features:**
- YAML-based scenario definition
- SQLite persistence with git commit tracking
- Parallel execution support
- Statistical comparison (t-test, Cohen's d)
- Markdown/HTML report generation

---

## Part 2: Integration Architecture

### 2.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    BioMate Test Harness                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐    ┌──────────────────┐                   │
│  │ BenchmarkSuite   │───▶│ SGIBenchAdapter  │◀── NEW            │
│  │ (orchestrator)   │    │ (bridge layer)   │                   │
│  └──────────────────┘    └────────┬─────────┘                   │
│                                   │                             │
│  ┌──────────────────┐    ┌────────▼─────────┐                   │
│  │ MetricsCollector │◀───│ SGIEvaluator     │◀── NEW            │
│  │ (measurements)   │    │ (task scoring)   │                   │
│  └──────────────────┘    └────────┬─────────┘                   │
│                                   │                             │
│  ┌──────────────────┐    ┌────────▼─────────┐                   │
│  │ ResultsAnalyzer  │◀───│ SGIResultsDB     │◀── NEW            │
│  │ (comparison)     │    │ (persistence)    │                   │
│  └──────────────────┘    └──────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SGI-Bench Datasets                         │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐        │
│  │ DeepResearch  │  │IdeaGeneration │  │ DryExperiment │  ...   │
│  │ (parquet)     │  │ (parquet)     │  │ (parquet)     │        │
│  └───────────────┘  └───────────────┘  └───────────────┘        │
└─────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                      LLM Providers                              │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐     │
│  │  OpenAI   │  │  Claude   │  │  Gemini   │  │  Local    │     │
│  │ GPT-4/5   │  │ Sonnet/Op │  │  Pro/Fla  │  │  Models   │     │
│  └───────────┘  └───────────┘  └───────────┘  └───────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Database Schema for Tracking

```sql
-- New tables for SGI-Bench integration

CREATE TABLE sgi_evaluation_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT UNIQUE,                    -- UUID for each run
    biomate_version TEXT,                  -- Git commit hash
    biomate_modifications TEXT,            -- JSON description of changes
    llm_model TEXT,                        -- e.g., "gpt-4.1", "claude-sonnet-4.5"
    llm_version TEXT,                      -- Model version/date
    domains TEXT,                          -- JSON: ["life", "chemistry"]
    tasks TEXT,                            -- JSON: ["deep_research", "idea_generation", ...]
    config JSON,                           -- Full configuration
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    status TEXT                            -- pending, running, completed, failed
);

CREATE TABLE sgi_task_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT,
    task_type TEXT,                        -- deep_research, idea_generation, etc.
    sample_id TEXT,                        -- Original dataset idx
    discipline TEXT,                       -- life, chemistry
    direction TEXT,                        -- Specific research direction

    -- Input/Output
    input_data JSON,                       -- Question/prompt
    model_output TEXT,                     -- Raw LLM response
    parsed_output JSON,                    -- Structured extraction

    -- Metrics (task-specific)
    exact_match FLOAT,
    step_level_accuracy FLOAT,
    novelty_score FLOAT,
    feasibility_score FLOAT,
    effectiveness_score FLOAT,
    detailedness_score FLOAT,
    final_score FLOAT,
    pass_at_1 FLOAT,
    pass_at_3 FLOAT,
    pass_at_5 FLOAT,
    sequence_similarity FLOAT,
    parameter_accuracy FLOAT,
    multi_choice_accuracy FLOAT,
    reasoning_validity FLOAT,

    -- Execution metadata
    runtime_seconds FLOAT,
    tokens_used INTEGER,
    error_message TEXT,

    FOREIGN KEY(run_id) REFERENCES sgi_evaluation_runs(run_id)
);

CREATE TABLE sgi_judge_votes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    result_id INTEGER,
    judge_model TEXT,                      -- gpt-5.1, gemini-3-pro, claude-sonnet-4.5
    dimension TEXT,                        -- novelty, feasibility, etc.
    vote TEXT,                             -- win, lose, tie
    position TEXT,                         -- normal, swapped
    reasoning TEXT,
    FOREIGN KEY(result_id) REFERENCES sgi_task_results(id)
);

-- Indexes for efficient querying
CREATE INDEX idx_results_run ON sgi_task_results(run_id);
CREATE INDEX idx_results_task ON sgi_task_results(task_type);
CREATE INDEX idx_results_discipline ON sgi_task_results(discipline);
CREATE INDEX idx_runs_model ON sgi_evaluation_runs(llm_model);
CREATE INDEX idx_runs_version ON sgi_evaluation_runs(biomate_version);
```

---

## Part 3: Implementation Plan

### 3.1 File Structure

```
/home/yzhang/biomate/research/benchmark_evaluation/
├── sgi_bench_datasets/              # Downloaded (DONE)
│   ├── SGI-DeepResearch/
│   ├── SGI-IdeaGeneration/
│   ├── SGI-DryExperiment/
│   ├── SGI-WetExperiment/
│   └── SGI-Reasoning/
│
├── SGI-Bench/                       # Cloned repo (DONE)
│   └── evaluation/
│
├── sgi_biomate_integration/         # NEW - Our integration code
│   ├── __init__.py
│   ├── config.py                    # Configuration management
│   ├── adapter.py                   # SGIBenchAdapter class
│   ├── evaluators/                  # Task-specific evaluators
│   │   ├── __init__.py
│   │   ├── deep_research.py
│   │   ├── idea_generation.py
│   │   ├── dry_experiment.py
│   │   ├── wet_experiment.py
│   │   └── reasoning.py
│   ├── llm_client.py               # Multi-provider LLM interface
│   ├── results_db.py               # SQLite persistence
│   ├── report_generator.py         # Markdown/HTML reports
│   └── cli.py                      # Command-line interface
│
├── scenarios/                       # YAML scenario definitions
│   ├── life_science_full.yml
│   ├── chemistry_full.yml
│   └── quick_validation.yml
│
├── results/                         # Evaluation results
│   ├── sgi_results.db              # SQLite database
│   └── reports/                    # Generated reports
│
└── scripts/                         # Utility scripts
    ├── run_evaluation.py
    ├── compare_models.py
    └── generate_report.py
```

### 3.2 Implementation Phases

#### Phase 1: Core Infrastructure (Priority: HIGH)

**1.1 Configuration Management** (`config.py`)
```python
@dataclass
class SGIBenchConfig:
    # Domains to evaluate
    disciplines: List[str] = field(default_factory=lambda: ["life", "chemistry"])

    # Tasks to run
    tasks: List[str] = field(default_factory=lambda: [
        "deep_research", "idea_generation", "dry_experiment",
        "wet_experiment", "reasoning"
    ])

    # LLM configuration
    primary_model: str = "gpt-4.1"
    judge_models: List[str] = field(default_factory=lambda: [
        "gpt-5.1", "gemini-3-pro", "claude-sonnet-4.5"
    ])

    # Execution settings
    max_workers: int = 10
    timeout_seconds: int = 300
    retry_attempts: int = 3

    # Tracking
    biomate_version: str = None  # Auto-detected from git
    modifications_description: str = ""

    # Paths
    datasets_dir: str = "./sgi_bench_datasets"
    results_db: str = "./results/sgi_results.db"
```

**1.2 LLM Client with Provider Abstraction** (`llm_client.py`)
```python
class UnifiedLLMClient:
    """Multi-provider LLM client for SGI-Bench evaluation"""

    def __init__(self, model: str, api_key: str = None):
        self.model = model
        self.provider = self._detect_provider(model)

    def chat(self, messages: List[Dict], **kwargs) -> str:
        """Unified chat interface across providers"""

    def chat_with_vision(self, messages: List[Dict], images: List[bytes]) -> str:
        """Vision-language model interface"""

    @staticmethod
    def _detect_provider(model: str) -> str:
        if model.startswith("gpt") or model.startswith("o"):
            return "openai"
        elif model.startswith("claude"):
            return "anthropic"
        elif model.startswith("gemini"):
            return "google"
        else:
            return "local"
```

**1.3 Results Database** (`results_db.py`)
```python
class SGIResultsDB:
    """SQLite persistence for SGI-Bench results with version tracking"""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self._init_db()

    def create_run(self, config: SGIBenchConfig) -> str:
        """Create a new evaluation run, return run_id"""

    def save_result(self, run_id: str, task_type: str, result: Dict):
        """Save individual task result"""

    def get_run_summary(self, run_id: str) -> Dict:
        """Get aggregated metrics for a run"""

    def compare_runs(self, run_ids: List[str]) -> pd.DataFrame:
        """Compare multiple runs across metrics"""

    def get_runs_by_model(self, model: str) -> List[Dict]:
        """Get all runs for a specific LLM"""

    def get_runs_by_biomate_version(self, version: str) -> List[Dict]:
        """Get all runs for a specific BioMate version"""
```

#### Phase 2: Task Evaluators (Priority: HIGH)

Each evaluator implements the same interface:

```python
class BaseEvaluator(ABC):
    def __init__(self, llm_client: UnifiedLLMClient, config: SGIBenchConfig):
        self.llm = llm_client
        self.config = config

    @abstractmethod
    def load_data(self, disciplines: List[str]) -> List[Dict]:
        """Load and filter dataset by discipline"""

    @abstractmethod
    def format_prompt(self, sample: Dict) -> str:
        """Format the prompt with few-shot examples"""

    @abstractmethod
    def parse_response(self, response: str) -> Dict:
        """Parse LLM response into structured format"""

    @abstractmethod
    def score(self, sample: Dict, parsed_response: Dict) -> Dict:
        """Calculate task-specific metrics"""

    def evaluate(self, sample: Dict) -> Dict:
        """Full evaluation pipeline for one sample"""
        prompt = self.format_prompt(sample)
        response = self.llm.chat([{"role": "user", "content": prompt}])
        parsed = self.parse_response(response)
        scores = self.score(sample, parsed)
        return {
            "input": sample,
            "output": response,
            "parsed": parsed,
            "scores": scores
        }
```

**Task-specific implementations:**

| Task | Few-Shot | Key Metrics | Judge Models |
|------|----------|-------------|--------------|
| `DeepResearchEvaluator` | Zero-shot | EM, SLA | o4-mini |
| `IdeaGenerationEvaluator` | One-shot JSON | Novelty, Feasibility, Effectiveness, Detailedness | 3 judges × 2 positions |
| `DryExperimentEvaluator` | Few-shot code | PassAll@k, SER, AET | o4-mini |
| `WetExperimentEvaluator` | Few-shot protocol | Sequence Similarity, Parameter Accuracy | None |
| `ReasoningEvaluator` | Zero-shot VLM | MCA, RV | o4-mini |

#### Phase 3: Orchestration & CLI (Priority: MEDIUM)

**3.1 SGI-Bench Adapter** (`adapter.py`)
```python
class SGIBenchAdapter:
    """Main orchestrator for SGI-Bench evaluation"""

    def __init__(self, config: SGIBenchConfig):
        self.config = config
        self.db = SGIResultsDB(config.results_db)
        self.llm = UnifiedLLMClient(config.primary_model)
        self.evaluators = self._init_evaluators()

    def run_evaluation(self) -> str:
        """Run full evaluation, return run_id"""
        run_id = self.db.create_run(self.config)

        for task in self.config.tasks:
            evaluator = self.evaluators[task]
            samples = evaluator.load_data(self.config.disciplines)

            results = parallel_map(
                evaluator.evaluate,
                samples,
                max_workers=self.config.max_workers
            )

            for result in results:
                self.db.save_result(run_id, task, result)

        return run_id

    def generate_report(self, run_id: str, format: str = "markdown") -> str:
        """Generate evaluation report"""
```

**3.2 Command-Line Interface** (`cli.py`)
```python
@click.group()
def cli():
    """SGI-Bench evaluation for BioMate"""
    pass

@cli.command()
@click.option("--model", default="gpt-4.1", help="LLM model to evaluate")
@click.option("--domains", default="life,chemistry", help="Domains to evaluate")
@click.option("--tasks", default="all", help="Tasks to run")
@click.option("--modifications", default="", help="Description of BioMate changes")
def run(model, domains, tasks, modifications):
    """Run SGI-Bench evaluation"""

@cli.command()
@click.argument("run_ids", nargs=-1)
def compare(run_ids):
    """Compare multiple evaluation runs"""

@cli.command()
@click.option("--model", help="Filter by model")
@click.option("--version", help="Filter by BioMate version")
def list_runs(model, version):
    """List evaluation runs"""

@cli.command()
@click.argument("run_id")
@click.option("--format", default="markdown", type=click.Choice(["markdown", "html", "json"]))
def report(run_id, format):
    """Generate evaluation report"""
```

#### Phase 4: Integration with BioMate Test Harness (Priority: MEDIUM)

Connect SGI-Bench adapter to the existing test harness:

```python
# In /home/yzhang/biomate/backend/lib/galaxy/ai/test_harness/benchmark_suite.py

class BenchmarkSuite:
    # ... existing code ...

    def run_sgi_benchmark(
        self,
        model: str,
        disciplines: List[str] = ["life", "chemistry"],
        tasks: List[str] = None,
        modifications: str = ""
    ) -> BenchmarkResults:
        """Run SGI-Bench evaluation through the test harness"""
        from sgi_biomate_integration import SGIBenchAdapter, SGIBenchConfig

        config = SGIBenchConfig(
            primary_model=model,
            disciplines=disciplines,
            tasks=tasks or ["deep_research", "idea_generation", "dry_experiment",
                          "wet_experiment", "reasoning"],
            biomate_version=self._get_git_commit(),
            modifications_description=modifications
        )

        adapter = SGIBenchAdapter(config)
        run_id = adapter.run_evaluation()

        # Convert to BenchmarkResults for compatibility
        return self._convert_sgi_results(run_id)
```

---

## Part 4: Execution Workflow

### 4.1 Running an Evaluation

```bash
# 1. Quick validation (subset of samples)
python -m sgi_biomate_integration.cli run \
    --model gpt-4.1 \
    --domains life,chemistry \
    --tasks deep_research,idea_generation \
    --modifications "Baseline evaluation"

# 2. Full evaluation for Life Science + Chemistry
python -m sgi_biomate_integration.cli run \
    --model gpt-4.1 \
    --domains life,chemistry \
    --tasks all \
    --modifications "v1.0 baseline"

# 3. Compare different LLMs
python -m sgi_biomate_integration.cli run --model gpt-4.1 --domains life,chemistry
python -m sgi_biomate_integration.cli run --model claude-sonnet-4.5 --domains life,chemistry
python -m sgi_biomate_integration.cli run --model gemini-3-pro --domains life,chemistry

python -m sgi_biomate_integration.cli compare <run_id_1> <run_id_2> <run_id_3>

# 4. Track BioMate modifications
python -m sgi_biomate_integration.cli run \
    --model gpt-4.1 \
    --modifications "Added workflow caching in WorkflowGenerator"

# 5. Generate report
python -m sgi_biomate_integration.cli report <run_id> --format markdown
```

### 4.2 Tracking Modifications

Each evaluation run records:
1. **Git commit hash** - Automatically captured
2. **Modifications description** - User-provided
3. **Full configuration** - JSON serialized
4. **Environment hash** - Python version, dependencies

Example comparison query:
```sql
SELECT
    r.biomate_version,
    r.modifications,
    r.llm_model,
    AVG(t.final_score) as avg_final_score,
    AVG(t.novelty_score) as avg_novelty,
    AVG(t.feasibility_score) as avg_feasibility
FROM sgi_evaluation_runs r
JOIN sgi_task_results t ON r.run_id = t.run_id
WHERE t.discipline IN ('life', 'chemistry')
GROUP BY r.run_id
ORDER BY r.started_at DESC;
```

---

## Part 5: Expected Outputs

### 5.1 Per-Run Summary

```json
{
  "run_id": "20251230-143000-abc123",
  "biomate_version": "097cb865",
  "modifications": "Baseline evaluation",
  "llm_model": "gpt-4.1",
  "domains": ["life", "chemistry"],
  "samples_evaluated": 407,
  "duration_minutes": 45.2,

  "scores": {
    "deep_research": {
      "exact_match": 0.142,
      "step_level_accuracy": 0.523
    },
    "idea_generation": {
      "novelty": 42.3,
      "feasibility": 18.7,
      "effectiveness": 35.2,
      "detailedness": 28.4,
      "final_score": 31.2
    },
    "dry_experiment": {
      "pass_at_1": 0.284,
      "pass_at_3": 0.312,
      "pass_at_5": 0.341,
      "smooth_execution_rate": 0.912
    },
    "wet_experiment": {
      "sequence_similarity": 0.287,
      "parameter_accuracy": 0.324
    },
    "reasoning": {
      "multi_choice_accuracy": 0.378,
      "reasoning_validity": 0.534
    }
  },

  "sgi_score": 28.4
}
```

### 5.2 Comparison Report

```markdown
# SGI-Bench Evaluation Comparison Report

## Models Compared
| Model | BioMate Version | Run Date | SGI-Score |
|-------|-----------------|----------|-----------|
| gpt-4.1 | 097cb865 | 2025-12-30 | 28.4 |
| claude-sonnet-4.5 | 097cb865 | 2025-12-30 | 31.2 |
| gemini-3-pro | 097cb865 | 2025-12-30 | 33.1 |

## Task Breakdown (Life Science + Chemistry)

### Idea Generation
| Model | Novelty | Feasibility | Effectiveness | Final |
|-------|---------|-------------|---------------|-------|
| gpt-4.1 | 42.3 | 18.7 | 35.2 | 31.2 |
| claude-sonnet-4.5 | 45.1 | 21.3 | 38.7 | 34.8 |
| gemini-3-pro | 48.2 | 19.8 | 41.2 | 36.4 |

### Key Findings
1. Gemini-3-Pro leads on Life Science tasks
2. Claude shows better feasibility scores
3. All models struggle with wet experiment protocols (< 35% similarity)
```

---

## Part 6: Timeline & Next Steps

### Immediate (This Session)
1. [x] Download datasets
2. [x] Clone SGI-Bench repo
3. [x] Document evaluation issues
4. [x] Create integration plan

### Phase 1: Core Infrastructure (Next)
1. [ ] Create `sgi_biomate_integration/` directory structure
2. [ ] Implement `config.py` with dataclasses
3. [ ] Implement `llm_client.py` with multi-provider support
4. [ ] Implement `results_db.py` with SQLite schema

### Phase 2: Evaluators
5. [ ] Implement `DeepResearchEvaluator`
6. [ ] Implement `IdeaGenerationEvaluator`
7. [ ] Implement `DryExperimentEvaluator`
8. [ ] Implement `WetExperimentEvaluator`
9. [ ] Implement `ReasoningEvaluator`

### Phase 3: Orchestration
10. [ ] Implement `adapter.py` main orchestrator
11. [ ] Implement `cli.py` command-line interface
12. [ ] Implement `report_generator.py`

### Phase 4: Validation & Integration
13. [ ] Run baseline evaluation on GPT-4.1
14. [ ] Compare against published SGI-Bench results
15. [ ] Integrate with BioMate test harness

---

## Appendix: Key Code References

### SGI-Bench Original Implementation
- **LLM Interface**: `SGI-Bench/evaluation/utils.py` - `LLM` class
- **Deep Research**: `SGI-Bench/evaluation/task_1_deep_research/`
- **Idea Generation**: `SGI-Bench/evaluation/task_2_idea_generation/`
- **Dry Experiment**: `SGI-Bench/evaluation/task_3_dry_experiment/`
- **Wet Experiment**: `SGI-Bench/evaluation/task_3_wet_experiment/`
- **Reasoning**: `SGI-Bench/evaluation/task_4_experimental_reasoning/`

### BioMate Test Harness
- **Suite**: `/home/yzhang/biomate/backend/lib/galaxy/ai/test_harness/benchmark_suite.py`
- **Metrics**: `/home/yzhang/biomate/backend/lib/galaxy/ai/test_harness/metrics_collector.py`
- **Analysis**: `/home/yzhang/biomate/backend/lib/galaxy/ai/test_harness/results_analyzer.py`
- **Knowledge**: `/home/yzhang/biomate/backend/lib/galaxy/ai/benchmark_knowledge.py`

### Dataset Locations
- **Local**: `/home/yzhang/biomate/research/benchmark_evaluation/sgi_bench_datasets/`
- **HuggingFace**: `InternScience/SGI-*`
