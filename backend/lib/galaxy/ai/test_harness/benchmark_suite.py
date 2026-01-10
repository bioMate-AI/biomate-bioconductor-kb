"""
Benchmark Suite

Framework for defining and running benchmark scenarios to compare
tools, parameters, and datasets.
"""

import logging
import json
import sqlite3
import time
import signal
from contextlib import contextmanager
from typing import Dict, List, Any, Optional, Callable
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from enum import Enum
import yaml
from concurrent.futures import ThreadPoolExecutor, as_completed, TimeoutError as FuturesTimeoutError

log = logging.getLogger(__name__)


class BenchmarkTimeoutError(Exception):
    """Raised when a benchmark run exceeds the configured timeout."""
    pass


@contextmanager
def timeout_handler(seconds: int, error_message: str = "Benchmark timed out"):
    """Context manager for timeout enforcement using signals (Unix only)."""
    def signal_handler(signum, frame):
        raise BenchmarkTimeoutError(error_message)

    # Only use signal-based timeout on Unix systems
    if hasattr(signal, 'SIGALRM'):
        original_handler = signal.signal(signal.SIGALRM, signal_handler)
        signal.alarm(seconds)
        try:
            yield
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, original_handler)
    else:
        # On Windows, yield without timeout enforcement
        yield


class BenchmarkStatus(str, Enum):
    """Benchmark run status."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETE = "complete"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass
class ToolConfig:
    """Configuration for a tool in a benchmark."""
    tool_id: str
    name: str
    versions: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class ParameterSet:
    """A set of parameters to test."""
    name: str
    params: Dict[str, Any]
    description: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class DatasetConfig:
    """Configuration for a benchmark dataset."""
    name: str
    path: str
    species: str = ""
    data_type: str = ""
    size_mb: float = 0.0
    sample_count: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class EvaluationConfig:
    """Configuration for result evaluation."""
    primary_metric: str = "runtime_seconds"
    secondary_metrics: List[str] = field(default_factory=list)
    statistical_test: str = "paired_ttest"
    significance_level: float = 0.05
    higher_is_better: Dict[str, bool] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class BenchmarkScenario:
    """
    A complete benchmark scenario definition.

    Defines what to compare:
    - tools: Which tools/methods to compare
    - parameter_sets: Which parameter combinations to test
    - datasets: Which datasets to test on
    - metrics: What to measure
    """
    name: str
    description: str
    tools: List[ToolConfig]
    parameter_sets: List[ParameterSet]
    datasets: List[DatasetConfig]
    metrics: List[str]
    evaluation: EvaluationConfig = field(default_factory=EvaluationConfig)
    repetitions: int = 3
    timeout_seconds: int = 3600
    parallel_runs: int = 1

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "description": self.description,
            "tools": [t.to_dict() for t in self.tools],
            "parameter_sets": [p.to_dict() for p in self.parameter_sets],
            "datasets": [d.to_dict() for d in self.datasets],
            "metrics": self.metrics,
            "evaluation": self.evaluation.to_dict(),
            "repetitions": self.repetitions,
            "timeout_seconds": self.timeout_seconds,
            "parallel_runs": self.parallel_runs
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "BenchmarkScenario":
        return cls(
            name=data["name"],
            description=data.get("description", ""),
            tools=[ToolConfig(**t) for t in data.get("tools", [])],
            parameter_sets=[ParameterSet(**p) for p in data.get("parameter_sets", [])],
            datasets=[DatasetConfig(**d) for d in data.get("datasets", [])],
            metrics=data.get("metrics", ["runtime_seconds"]),
            evaluation=EvaluationConfig(**data.get("evaluation", {})),
            repetitions=data.get("repetitions", 3),
            timeout_seconds=data.get("timeout_seconds", 3600),
            parallel_runs=data.get("parallel_runs", 1)
        )

    @classmethod
    def from_yaml(cls, yaml_path: str) -> "BenchmarkScenario":
        """Load scenario from YAML file."""
        with open(yaml_path) as f:
            data = yaml.safe_load(f)
        return cls.from_dict(data)


@dataclass
class BenchmarkRun:
    """A single benchmark run (one tool + params + dataset + repetition)."""
    run_id: str
    scenario_name: str
    tool_id: str
    tool_version: str
    parameter_set: str
    dataset_name: str
    repetition: int
    status: BenchmarkStatus = BenchmarkStatus.PENDING
    started_at: Optional[str] = None
    completed_at: Optional[str] = None

    # Results
    runtime_seconds: Optional[float] = None
    peak_memory_gb: Optional[float] = None
    cpu_utilization: Optional[float] = None
    output_size_mb: Optional[float] = None
    quality_metrics: Dict[str, float] = field(default_factory=dict)

    success: bool = True
    error_message: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "run_id": self.run_id,
            "scenario_name": self.scenario_name,
            "tool_id": self.tool_id,
            "tool_version": self.tool_version,
            "parameter_set": self.parameter_set,
            "dataset_name": self.dataset_name,
            "repetition": self.repetition,
            "status": self.status.value,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "runtime_seconds": self.runtime_seconds,
            "peak_memory_gb": self.peak_memory_gb,
            "cpu_utilization": self.cpu_utilization,
            "output_size_mb": self.output_size_mb,
            "quality_metrics": self.quality_metrics,
            "success": self.success,
            "error_message": self.error_message
        }


@dataclass
class BenchmarkResults:
    """Results from a complete benchmark scenario."""
    scenario_name: str
    started_at: str
    completed_at: Optional[str] = None
    status: BenchmarkStatus = BenchmarkStatus.RUNNING
    git_commit: Optional[str] = None
    environment_hash: Optional[str] = None

    runs: List[BenchmarkRun] = field(default_factory=list)

    # Summary statistics
    summary: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "scenario_name": self.scenario_name,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "status": self.status.value,
            "git_commit": self.git_commit,
            "environment_hash": self.environment_hash,
            "runs": [r.to_dict() for r in self.runs],
            "summary": self.summary
        }

    def get_runs_by_tool(self, tool_id: str) -> List[BenchmarkRun]:
        """Get all runs for a specific tool."""
        return [r for r in self.runs if r.tool_id == tool_id]

    def get_runs_by_params(self, param_set: str) -> List[BenchmarkRun]:
        """Get all runs for a specific parameter set."""
        return [r for r in self.runs if r.parameter_set == param_set]

    def get_runs_by_dataset(self, dataset: str) -> List[BenchmarkRun]:
        """Get all runs for a specific dataset."""
        return [r for r in self.runs if r.dataset_name == dataset]

    def calculate_summary(self):
        """Calculate summary statistics."""
        if not self.runs:
            return

        successful_runs = [r for r in self.runs if r.success]

        self.summary = {
            "total_runs": len(self.runs),
            "successful_runs": len(successful_runs),
            "failed_runs": len(self.runs) - len(successful_runs),
            "tools_tested": len(set(r.tool_id for r in self.runs)),
            "datasets_tested": len(set(r.dataset_name for r in self.runs)),
            "param_sets_tested": len(set(r.parameter_set for r in self.runs))
        }

        if successful_runs:
            runtimes = [r.runtime_seconds for r in successful_runs if r.runtime_seconds]
            if runtimes:
                self.summary["avg_runtime_seconds"] = sum(runtimes) / len(runtimes)
                self.summary["min_runtime_seconds"] = min(runtimes)
                self.summary["max_runtime_seconds"] = max(runtimes)

            memories = [r.peak_memory_gb for r in successful_runs if r.peak_memory_gb]
            if memories:
                self.summary["avg_memory_gb"] = sum(memories) / len(memories)


class BenchmarkResultsDB:
    """SQLite database for storing benchmark results."""

    def __init__(self, db_path: str = None):
        if db_path is None:
            db_path = Path(__file__).parent.parent.parent.parent.parent / "database" / "benchmark_results.db"

        self.db_path = str(db_path)
        self._init_schema()

    def _init_schema(self):
        """Initialize database schema."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            cursor.execute("""
                CREATE TABLE IF NOT EXISTS benchmark_runs (
                    id INTEGER PRIMARY KEY,
                    scenario_name TEXT NOT NULL,
                    run_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    git_commit TEXT,
                    environment_hash TEXT,
                    status TEXT,
                    summary JSON,
                    results_json JSON
                )
            """)

            cursor.execute("""
                CREATE TABLE IF NOT EXISTS benchmark_results (
                    id INTEGER PRIMARY KEY,
                    run_id INTEGER REFERENCES benchmark_runs(id),
                    tool_id TEXT NOT NULL,
                    tool_version TEXT,
                    parameter_set TEXT,
                    dataset_name TEXT,
                    repetition INTEGER,
                    runtime_seconds FLOAT,
                    peak_memory_gb FLOAT,
                    cpu_utilization FLOAT,
                    quality_metrics JSON,
                    output_size_mb FLOAT,
                    success BOOLEAN,
                    error_message TEXT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_benchmark_results_tool
                ON benchmark_results(tool_id)
            """)

            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_benchmark_results_scenario
                ON benchmark_results(run_id)
            """)

            conn.commit()
        finally:
            conn.close()

    def save_results(self, results: BenchmarkResults) -> int:
        """Save benchmark results to database."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            cursor.execute("""
                INSERT INTO benchmark_runs (scenario_name, git_commit, environment_hash, status, summary, results_json)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                results.scenario_name,
                results.git_commit,
                results.environment_hash,
                results.status.value,
                json.dumps(results.summary),
                json.dumps(results.to_dict())
            ))

            run_id = cursor.lastrowid

            # Save individual results
            for run in results.runs:
                cursor.execute("""
                    INSERT INTO benchmark_results
                    (run_id, tool_id, tool_version, parameter_set, dataset_name, repetition,
                     runtime_seconds, peak_memory_gb, cpu_utilization, quality_metrics,
                     output_size_mb, success, error_message)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    run_id,
                    run.tool_id,
                    run.tool_version,
                    run.parameter_set,
                    run.dataset_name,
                    run.repetition,
                    run.runtime_seconds,
                    run.peak_memory_gb,
                    run.cpu_utilization,
                    json.dumps(run.quality_metrics),
                    run.output_size_mb,
                    run.success,
                    run.error_message
                ))

            conn.commit()
            return run_id
        finally:
            conn.close()

    def get_results(self, run_id: int) -> Optional[BenchmarkResults]:
        """Load benchmark results from database."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            cursor.execute("""
                SELECT results_json FROM benchmark_runs WHERE id = ?
            """, (run_id,))

            row = cursor.fetchone()

            if not row:
                return None

            data = json.loads(row[0])

            results = BenchmarkResults(
                scenario_name=data["scenario_name"],
                started_at=data["started_at"],
                completed_at=data.get("completed_at"),
                status=BenchmarkStatus(data["status"]),
                git_commit=data.get("git_commit"),
                environment_hash=data.get("environment_hash"),
                summary=data.get("summary", {})
            )

            for run_data in data.get("runs", []):
                run = BenchmarkRun(
                    run_id=run_data["run_id"],
                    scenario_name=run_data["scenario_name"],
                    tool_id=run_data["tool_id"],
                    tool_version=run_data["tool_version"],
                    parameter_set=run_data["parameter_set"],
                    dataset_name=run_data["dataset_name"],
                    repetition=run_data["repetition"],
                    status=BenchmarkStatus(run_data["status"]),
                    started_at=run_data.get("started_at"),
                    completed_at=run_data.get("completed_at"),
                    runtime_seconds=run_data.get("runtime_seconds"),
                    peak_memory_gb=run_data.get("peak_memory_gb"),
                    cpu_utilization=run_data.get("cpu_utilization"),
                    output_size_mb=run_data.get("output_size_mb"),
                    quality_metrics=run_data.get("quality_metrics", {}),
                    success=run_data.get("success", True),
                    error_message=run_data.get("error_message")
                )
                results.runs.append(run)

            return results
        finally:
            conn.close()

    def list_runs(self, scenario_name: str = None, limit: int = 100) -> List[Dict[str, Any]]:
        """List benchmark runs."""
        conn = sqlite3.connect(self.db_path)
        try:
            cursor = conn.cursor()

            if scenario_name:
                cursor.execute("""
                    SELECT id, scenario_name, run_timestamp, status, summary
                    FROM benchmark_runs
                    WHERE scenario_name = ?
                    ORDER BY run_timestamp DESC
                    LIMIT ?
                """, (scenario_name, limit))
            else:
                cursor.execute("""
                    SELECT id, scenario_name, run_timestamp, status, summary
                    FROM benchmark_runs
                    ORDER BY run_timestamp DESC
                    LIMIT ?
                """, (limit,))

            runs = []
            for row in cursor.fetchall():
                runs.append({
                    "id": row[0],
                    "scenario_name": row[1],
                    "run_timestamp": row[2],
                    "status": row[3],
                    "summary": json.loads(row[4]) if row[4] else {}
                })

            return runs
        finally:
            conn.close()


class BenchmarkSuite:
    """
    Main class for managing and running benchmarks.

    Example usage:
        suite = BenchmarkSuite()
        scenario = BenchmarkScenario.from_yaml("rna_seq_aligners.yml")
        suite.add_scenario(scenario)
        results = suite.run_scenario("rna_seq_aligners", executor=my_executor)
        report = suite.compare("rna_seq_aligners")
    """

    def __init__(
        self,
        scenarios_dir: str = None,
        results_db: BenchmarkResultsDB = None
    ):
        """
        Initialize benchmark suite.

        Args:
            scenarios_dir: Directory containing scenario YAML files
            results_db: Database for storing results
        """
        self.scenarios: Dict[str, BenchmarkScenario] = {}
        self.results_db = results_db or BenchmarkResultsDB()

        if scenarios_dir:
            self._load_scenarios(scenarios_dir)

    def _load_scenarios(self, scenarios_dir: str):
        """Load all scenarios from directory."""
        path = Path(scenarios_dir)
        if not path.exists():
            log.warning(f"Scenarios directory not found: {scenarios_dir}")
            return

        for yaml_file in path.glob("*.yml"):
            try:
                scenario = BenchmarkScenario.from_yaml(str(yaml_file))
                self.scenarios[scenario.name] = scenario
                log.info(f"Loaded scenario: {scenario.name}")
            except Exception as e:
                log.error(f"Failed to load scenario {yaml_file}: {e}")

    def add_scenario(self, scenario: BenchmarkScenario):
        """Add a scenario to the suite."""
        self.scenarios[scenario.name] = scenario

    def list_scenarios(self) -> List[str]:
        """List all available scenarios."""
        return list(self.scenarios.keys())

    def get_scenario(self, name: str) -> Optional[BenchmarkScenario]:
        """Get a scenario by name."""
        return self.scenarios.get(name)

    def run_scenario(
        self,
        name: str,
        executor: Callable[[str, str, Dict[str, Any], str], Dict[str, Any]] = None,
        datasets: List[str] = None,
        tools: List[str] = None
    ) -> BenchmarkResults:
        """
        Run a benchmark scenario.

        Args:
            name: Scenario name
            executor: Function to execute a tool
                      executor(tool_id, dataset_path, params, output_dir) -> metrics_dict
            datasets: Optional list of datasets to run (filters scenario)
            tools: Optional list of tools to run (filters scenario)

        Returns:
            BenchmarkResults with all run data
        """
        scenario = self.scenarios.get(name)
        if not scenario:
            raise ValueError(f"Unknown scenario: {name}")

        log.info(f"Starting benchmark: {name}")

        results = BenchmarkResults(
            scenario_name=name,
            started_at=datetime.now().isoformat(),
            git_commit=self._get_git_commit(),
            environment_hash=self._get_environment_hash()
        )

        # Generate all runs
        run_configs = self._generate_run_configs(scenario, datasets, tools)
        log.info(f"Generated {len(run_configs)} run configurations")

        # Execute runs
        if scenario.parallel_runs > 1 and executor:
            results.runs = self._run_parallel(run_configs, executor, scenario)
        else:
            results.runs = self._run_sequential(run_configs, executor, scenario)

        # Calculate summary
        results.completed_at = datetime.now().isoformat()
        results.status = BenchmarkStatus.COMPLETE
        results.calculate_summary()

        # Save to database
        run_id = self.results_db.save_results(results)
        log.info(f"Saved benchmark results with ID: {run_id}")

        return results

    def _generate_run_configs(
        self,
        scenario: BenchmarkScenario,
        datasets: List[str] = None,
        tools: List[str] = None
    ) -> List[BenchmarkRun]:
        """Generate all run configurations for a scenario."""
        runs = []
        run_counter = 0

        # Filter tools and datasets if specified
        scenario_tools = scenario.tools
        if tools:
            scenario_tools = [t for t in scenario_tools if t.tool_id in tools]

        scenario_datasets = scenario.datasets
        if datasets:
            scenario_datasets = [d for d in scenario_datasets if d.name in datasets]

        for tool in scenario_tools:
            versions = tool.versions or ["latest"]
            for version in versions:
                for param_set in scenario.parameter_sets:
                    for dataset in scenario_datasets:
                        for rep in range(1, scenario.repetitions + 1):
                            run_counter += 1
                            run = BenchmarkRun(
                                run_id=f"run_{run_counter:04d}",
                                scenario_name=scenario.name,
                                tool_id=tool.tool_id,
                                tool_version=version,
                                parameter_set=param_set.name,
                                dataset_name=dataset.name,
                                repetition=rep
                            )
                            runs.append(run)

        return runs

    def _run_sequential(
        self,
        runs: List[BenchmarkRun],
        executor: Callable,
        scenario: BenchmarkScenario
    ) -> List[BenchmarkRun]:
        """Run benchmarks sequentially with timeout enforcement."""
        completed_runs = []
        timeout_seconds = scenario.timeout_seconds

        for i, run in enumerate(runs):
            log.info(f"Running {i+1}/{len(runs)}: {run.tool_id} / {run.parameter_set} / {run.dataset_name}")

            run.status = BenchmarkStatus.RUNNING
            run.started_at = datetime.now().isoformat()

            try:
                if executor:
                    # Get parameters and dataset
                    param_set = next(p for p in scenario.parameter_sets if p.name == run.parameter_set)
                    dataset = next(d for d in scenario.datasets if d.name == run.dataset_name)

                    # Execute with timeout
                    start_time = time.time()
                    with timeout_handler(
                        timeout_seconds,
                        f"Run {run.run_id} exceeded timeout of {timeout_seconds}s"
                    ):
                        metrics = executor(
                            run.tool_id,
                            dataset.path,
                            param_set.params,
                            f"/tmp/benchmark_{run.run_id}"
                        )
                    elapsed = time.time() - start_time

                    # Record metrics
                    run.runtime_seconds = metrics.get("runtime_seconds", elapsed)
                    run.peak_memory_gb = metrics.get("peak_memory_gb", 0)
                    run.cpu_utilization = metrics.get("cpu_utilization", 0)
                    run.output_size_mb = metrics.get("output_size_mb", 0)
                    run.quality_metrics = metrics.get("quality_metrics", {})
                    run.success = True
                else:
                    # Dry run - simulate
                    run.runtime_seconds = 10.0
                    run.peak_memory_gb = 1.0
                    run.success = True

                run.status = BenchmarkStatus.COMPLETE

            except BenchmarkTimeoutError as e:
                log.error(f"Run timed out: {e}")
                run.status = BenchmarkStatus.FAILED
                run.success = False
                run.error_message = f"Timeout after {timeout_seconds}s"
            except Exception as e:
                log.error(f"Run failed: {e}")
                run.status = BenchmarkStatus.FAILED
                run.success = False
                run.error_message = str(e)

            run.completed_at = datetime.now().isoformat()
            completed_runs.append(run)

        return completed_runs

    def _run_parallel(
        self,
        runs: List[BenchmarkRun],
        executor: Callable,
        scenario: BenchmarkScenario
    ) -> List[BenchmarkRun]:
        """Run benchmarks in parallel with timeout enforcement."""
        completed_runs = []
        timeout_seconds = scenario.timeout_seconds

        def execute_run(run: BenchmarkRun) -> BenchmarkRun:
            run.status = BenchmarkStatus.RUNNING
            run.started_at = datetime.now().isoformat()

            try:
                param_set = next(p for p in scenario.parameter_sets if p.name == run.parameter_set)
                dataset = next(d for d in scenario.datasets if d.name == run.dataset_name)

                start_time = time.time()
                metrics = executor(
                    run.tool_id,
                    dataset.path,
                    param_set.params,
                    f"/tmp/benchmark_{run.run_id}"
                )
                elapsed = time.time() - start_time

                run.runtime_seconds = metrics.get("runtime_seconds", elapsed)
                run.peak_memory_gb = metrics.get("peak_memory_gb", 0)
                run.cpu_utilization = metrics.get("cpu_utilization", 0)
                run.output_size_mb = metrics.get("output_size_mb", 0)
                run.quality_metrics = metrics.get("quality_metrics", {})
                run.success = True
                run.status = BenchmarkStatus.COMPLETE

            except Exception as e:
                run.status = BenchmarkStatus.FAILED
                run.success = False
                run.error_message = str(e)

            run.completed_at = datetime.now().isoformat()
            return run

        with ThreadPoolExecutor(max_workers=scenario.parallel_runs) as pool:
            futures = {pool.submit(execute_run, run): run for run in runs}

            for future in as_completed(futures, timeout=timeout_seconds):
                try:
                    completed_run = future.result(timeout=timeout_seconds)
                    completed_runs.append(completed_run)
                    log.info(f"Completed: {completed_run.tool_id} / {completed_run.parameter_set}")
                except FuturesTimeoutError:
                    # Find the run associated with this future
                    run = futures[future]
                    run.status = BenchmarkStatus.FAILED
                    run.success = False
                    run.error_message = f"Timeout after {timeout_seconds}s"
                    run.completed_at = datetime.now().isoformat()
                    completed_runs.append(run)
                    log.error(f"Timed out: {run.tool_id} / {run.parameter_set}")

        return completed_runs

    def run_all(
        self,
        executor: Callable = None,
        parallel: bool = False
    ) -> Dict[str, BenchmarkResults]:
        """Run all registered scenarios."""
        all_results = {}

        for name in self.scenarios:
            try:
                results = self.run_scenario(name, executor)
                all_results[name] = results
            except Exception as e:
                log.error(f"Failed to run scenario {name}: {e}")

        return all_results

    def compare(
        self,
        scenario_name: str,
        run_id: int = None
    ) -> Dict[str, Any]:
        """
        Generate comparison report for a scenario.

        Args:
            scenario_name: Scenario to compare
            run_id: Specific run ID (uses latest if None)

        Returns:
            Comparison report dictionary
        """
        if run_id:
            results = self.results_db.get_results(run_id)
        else:
            # Get latest run for this scenario
            runs = self.results_db.list_runs(scenario_name, limit=1)
            if not runs:
                raise ValueError(f"No runs found for scenario: {scenario_name}")
            results = self.results_db.get_results(runs[0]["id"])

        if not results:
            raise ValueError(f"Results not found")

        # Generate comparison
        from .results_analyzer import ResultsAnalyzer
        analyzer = ResultsAnalyzer()
        return analyzer.compare_tools(results)

    def _get_git_commit(self) -> Optional[str]:
        """Get current git commit hash."""
        try:
            import subprocess
            result = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                capture_output=True,
                text=True
            )
            return result.stdout.strip()[:8]
        except (subprocess.SubprocessError, OSError, FileNotFoundError):
            return None

    def _get_environment_hash(self) -> Optional[str]:
        """Get hash of current environment."""
        import hashlib
        import sys
        env_str = f"{sys.version}_{sys.platform}"
        return hashlib.md5(env_str.encode()).hexdigest()[:8]
