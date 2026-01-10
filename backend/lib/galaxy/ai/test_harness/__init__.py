"""
BioMate Test Harness

A framework for benchmarking and comparing:
- Different bioinformatics tools/methods
- Different parameter settings
- Performance across different datasets

Per-user, per-project, and per-dataset evaluation system aligned with
scientific evaluation standards (SGI-Bench PIM model).
"""

from typing import Dict, Any, Optional

from .benchmark_suite import BenchmarkSuite, BenchmarkScenario, BenchmarkResults, BenchmarkResultsDB
from .metrics_collector import MetricsCollector, JobMetrics
from .results_analyzer import ResultsAnalyzer, ComparisonReport
from .user_context import (
    UserBenchmarkContext,
    UserProject,
    UserDataset,
    UserContextDB,
    EvaluationDomain,
    EvaluationTask,
    EvaluationCriteria,
    get_or_create_user_context,
    create_default_evaluation_criteria
)
from .sgi_bench_adapter import (
    SGIBenchDataLoader,
    SGIPromptTemplates,
    SGIScorer,
    SGISample,
    SGIDiscipline,
    SGITaskType,
    FewShotExample,
    create_few_shot_examples
)
from .evaluators import (
    BaseEvaluator,
    ToolEvaluator,
    WorkflowEvaluator,
    ScientificEvaluator,
    CompositeEvaluator,
    EvaluationResult,
    EvaluationReport,
    run_sgi_bench_evaluation
)


def load_benchmark_results(scenario: str, run_id: int = None) -> Optional[Dict[str, Any]]:
    """
    Load benchmark results for a scenario.

    Args:
        scenario: Name of the benchmark scenario
        run_id: Specific run ID to load (uses latest if None)

    Returns:
        Dictionary with benchmark results or None if not found
    """
    db = BenchmarkResultsDB()

    if run_id:
        results = db.get_results(run_id)
    else:
        # Get latest run for this scenario
        runs = db.list_runs(scenario, limit=1)
        if not runs:
            return None
        results = db.get_results(runs[0]["id"])

    if results:
        return results.to_dict()
    return None


def get_benchmark_suite() -> BenchmarkSuite:
    """Get a configured BenchmarkSuite instance."""
    return BenchmarkSuite()


__all__ = [
    # Benchmark Suite
    "BenchmarkSuite",
    "BenchmarkScenario",
    "BenchmarkResults",
    "BenchmarkResultsDB",
    # Metrics
    "MetricsCollector",
    "JobMetrics",
    # Results Analysis
    "ResultsAnalyzer",
    "ComparisonReport",
    # User Context
    "UserBenchmarkContext",
    "UserProject",
    "UserDataset",
    "UserContextDB",
    "EvaluationDomain",
    "EvaluationTask",
    "EvaluationCriteria",
    # SGI-Bench Integration
    "SGIBenchDataLoader",
    "SGIPromptTemplates",
    "SGIScorer",
    "SGISample",
    "SGIDiscipline",
    "SGITaskType",
    "FewShotExample",
    # Evaluators
    "BaseEvaluator",
    "ToolEvaluator",
    "WorkflowEvaluator",
    "ScientificEvaluator",
    "CompositeEvaluator",
    "EvaluationResult",
    "EvaluationReport",
    # Helper Functions
    "load_benchmark_results",
    "get_benchmark_suite",
    "get_or_create_user_context",
    "create_default_evaluation_criteria",
    "create_few_shot_examples",
    "run_sgi_bench_evaluation"
]
