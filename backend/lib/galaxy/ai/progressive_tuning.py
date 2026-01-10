"""
Progressive Tuning Controller

Implements the "small data first" approach for parameter tuning:
1. Run pilot analysis on subset of data
2. Optimize parameters based on pilot results
3. Review and approve parameters
4. Execute full analysis with optimized settings
"""

import logging
import time
import json
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from enum import Enum

log = logging.getLogger(__name__)


class SamplingStrategy(str, Enum):
    """Available sampling strategies."""
    RANDOM = "random"
    STRATIFIED = "stratified"
    FIRST_N = "first_n"
    REPRESENTATIVE = "representative"
    CHROMOSOME = "chromosome"  # For genomic data


class OptimizationMetric(str, Enum):
    """Metrics to optimize for."""
    RUNTIME = "runtime"
    MEMORY = "memory"
    QUALITY = "quality"
    BALANCED = "balanced"


@dataclass
class TuningConfig:
    """Configuration for progressive tuning."""
    # Pilot run settings
    pilot_fraction: float = 0.1  # 10% of data
    min_pilot_samples: int = 3
    max_pilot_samples: int = 50
    sampling_strategy: SamplingStrategy = SamplingStrategy.STRATIFIED
    strata_column: Optional[str] = None  # Column for stratified sampling

    # Optimization settings
    auto_optimize: bool = False
    optimization_budget: int = 5  # Max parameter combinations to try
    optimization_metric: OptimizationMetric = OptimizationMetric.BALANCED

    # Timeouts
    pilot_timeout_seconds: int = 1800  # 30 min
    optimization_timeout_seconds: int = 3600  # 1 hour

    def to_dict(self) -> Dict[str, Any]:
        return {
            "pilot_fraction": self.pilot_fraction,
            "min_pilot_samples": self.min_pilot_samples,
            "max_pilot_samples": self.max_pilot_samples,
            "sampling_strategy": self.sampling_strategy.value,
            "strata_column": self.strata_column,
            "auto_optimize": self.auto_optimize,
            "optimization_budget": self.optimization_budget,
            "optimization_metric": self.optimization_metric.value,
            "pilot_timeout_seconds": self.pilot_timeout_seconds,
            "optimization_timeout_seconds": self.optimization_timeout_seconds
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TuningConfig":
        return cls(
            pilot_fraction=data.get("pilot_fraction", 0.1),
            min_pilot_samples=data.get("min_pilot_samples", 3),
            max_pilot_samples=data.get("max_pilot_samples", 50),
            sampling_strategy=SamplingStrategy(data.get("sampling_strategy", "stratified")),
            strata_column=data.get("strata_column"),
            auto_optimize=data.get("auto_optimize", False),
            optimization_budget=data.get("optimization_budget", 5),
            optimization_metric=OptimizationMetric(data.get("optimization_metric", "balanced")),
            pilot_timeout_seconds=data.get("pilot_timeout_seconds", 1800),
            optimization_timeout_seconds=data.get("optimization_timeout_seconds", 3600)
        )


@dataclass
class SamplingReport:
    """Report on data sampling."""
    total_samples: int
    selected_samples: int
    strategy_used: str
    strata_distribution: Optional[Dict[str, int]] = None
    sample_ids: List[str] = field(default_factory=list)
    sampling_seed: int = 42

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class PilotMetrics:
    """Metrics collected from pilot run."""
    runtime_seconds: float
    peak_memory_gb: float
    cpu_utilization: float = 0.0
    output_file_count: int = 0
    output_size_mb: float = 0.0

    # Quality metrics (analysis-specific)
    quality_metrics: Dict[str, float] = field(default_factory=dict)

    # Per-step metrics
    step_metrics: Dict[str, Dict[str, float]] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class PilotResult:
    """Result of a pilot run."""
    pilot_id: str
    workflow_id: str
    status: str  # 'running', 'complete', 'failed'
    config: TuningConfig
    sampling_report: SamplingReport
    metrics: Optional[PilotMetrics] = None
    parameters_used: Dict[str, Any] = field(default_factory=dict)
    started_at: str = ""
    completed_at: Optional[str] = None
    error_message: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "pilot_id": self.pilot_id,
            "workflow_id": self.workflow_id,
            "status": self.status,
            "config": self.config.to_dict(),
            "sampling_report": self.sampling_report.to_dict(),
            "metrics": self.metrics.to_dict() if self.metrics else None,
            "parameters_used": self.parameters_used,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
            "error_message": self.error_message
        }


@dataclass
class FullRunEstimate:
    """Estimated resources for full run."""
    estimated_runtime_seconds: float
    estimated_runtime_display: str
    estimated_memory_gb: float
    estimated_cost_usd: Optional[float] = None
    confidence: float = 0.8
    scaling_factors: Dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class ParameterRecommendation:
    """Recommended parameter setting from optimization."""
    parameter_name: str
    recommended_value: Any
    current_value: Any
    improvement_percent: float
    confidence: float
    reason: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class OptimizationResult:
    """Result of parameter optimization."""
    best_parameters: Dict[str, Any]
    recommendations: List[ParameterRecommendation]
    iterations_run: int
    metric_improvement: float
    comparison_results: List[Dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "best_parameters": self.best_parameters,
            "recommendations": [r.to_dict() for r in self.recommendations],
            "iterations_run": self.iterations_run,
            "metric_improvement": self.metric_improvement,
            "comparison_results": self.comparison_results
        }


class DataSampler:
    """
    Handles data sampling for pilot runs.

    Supports multiple strategies:
    - Random: Simple random sampling
    - Stratified: Preserve group proportions
    - First_N: Take first N samples
    - Representative: Select diverse samples
    """

    def __init__(self, seed: int = 42):
        self.seed = seed
        import random
        self.rng = random.Random(seed)

    @staticmethod
    def random_sample(data: List, fraction: float, seed: int = 42) -> List:
        """
        Simple random sampling (static convenience method).

        Args:
            data: List of items to sample from
            fraction: Fraction of items to select (0-1)
            seed: Random seed for reproducibility

        Returns:
            Sampled list
        """
        import random
        rng = random.Random(seed)
        count = max(1, int(len(data) * fraction))
        return rng.sample(data, min(count, len(data)))

    @staticmethod
    def first_n(data: List, n: int) -> List:
        """
        Take first N items (static convenience method).

        Args:
            data: List of items
            n: Number of items to take

        Returns:
            First n items
        """
        return data[:n]

    @staticmethod
    def stratified_sample(
        data: List,
        fraction: float,
        strata: Dict[Any, str],
        seed: int = 42
    ) -> List:
        """
        Stratified sampling (static convenience method).

        Args:
            data: List of items to sample from
            fraction: Fraction of items to select (0-1)
            strata: Mapping of item -> stratum label
            seed: Random seed

        Returns:
            Stratified sampled list
        """
        import random
        rng = random.Random(seed)

        # Group by stratum
        groups: Dict[str, List] = {}
        for item in data:
            stratum = strata.get(item, "unknown")
            if stratum not in groups:
                groups[stratum] = []
            groups[stratum].append(item)

        # Sample proportionally from each group
        result = []
        total_count = max(1, int(len(data) * fraction))

        for stratum, items in groups.items():
            proportion = len(items) / len(data)
            stratum_count = max(1, int(total_count * proportion))
            stratum_count = min(stratum_count, len(items))
            result.extend(rng.sample(items, stratum_count))

        return result

    def sample(
        self,
        sample_ids: List[str],
        config: TuningConfig,
        metadata: Optional[Dict[str, Dict[str, Any]]] = None
    ) -> SamplingReport:
        """
        Sample data according to configuration.

        Args:
            sample_ids: List of sample identifiers
            config: Tuning configuration
            metadata: Optional metadata for each sample (for stratified sampling)

        Returns:
            SamplingReport with selected samples
        """
        total = len(sample_ids)

        # Calculate target sample count
        target_count = int(total * config.pilot_fraction)
        target_count = max(config.min_pilot_samples, target_count)
        target_count = min(config.max_pilot_samples, target_count, total)

        strategy = config.sampling_strategy

        if strategy == SamplingStrategy.RANDOM:
            selected, strata = self._random_sample(sample_ids, target_count)
        elif strategy == SamplingStrategy.STRATIFIED:
            selected, strata = self._stratified_sample(
                sample_ids, target_count, metadata, config.strata_column
            )
        elif strategy == SamplingStrategy.FIRST_N:
            selected, strata = self._first_n_sample(sample_ids, target_count)
        elif strategy == SamplingStrategy.REPRESENTATIVE:
            selected, strata = self._representative_sample(
                sample_ids, target_count, metadata
            )
        else:
            selected, strata = self._random_sample(sample_ids, target_count)

        return SamplingReport(
            total_samples=total,
            selected_samples=len(selected),
            strategy_used=strategy.value,
            strata_distribution=strata,
            sample_ids=selected,
            sampling_seed=self.seed
        )

    def _random_sample(
        self,
        sample_ids: List[str],
        count: int
    ) -> Tuple[List[str], Optional[Dict[str, int]]]:
        """Simple random sampling."""
        selected = self.rng.sample(sample_ids, min(count, len(sample_ids)))
        return selected, None

    def _stratified_sample(
        self,
        sample_ids: List[str],
        count: int,
        metadata: Optional[Dict[str, Dict[str, Any]]],
        strata_column: Optional[str]
    ) -> Tuple[List[str], Optional[Dict[str, int]]]:
        """Stratified sampling to preserve group proportions."""
        if not metadata or not strata_column:
            return self._random_sample(sample_ids, count)

        # Group samples by stratum
        strata_groups: Dict[str, List[str]] = {}
        for sample_id in sample_ids:
            sample_meta = metadata.get(sample_id, {})
            stratum = str(sample_meta.get(strata_column, "unknown"))
            if stratum not in strata_groups:
                strata_groups[stratum] = []
            strata_groups[stratum].append(sample_id)

        # Sample proportionally from each stratum
        selected = []
        strata_counts = {}

        for stratum, samples in strata_groups.items():
            # Calculate proportional count
            proportion = len(samples) / len(sample_ids)
            stratum_count = max(1, int(count * proportion))
            stratum_count = min(stratum_count, len(samples))

            stratum_selected = self.rng.sample(samples, stratum_count)
            selected.extend(stratum_selected)
            strata_counts[stratum] = len(stratum_selected)

        return selected, strata_counts

    def _first_n_sample(
        self,
        sample_ids: List[str],
        count: int
    ) -> Tuple[List[str], Optional[Dict[str, int]]]:
        """Take first N samples (useful for ordered data)."""
        return sample_ids[:count], None

    def _representative_sample(
        self,
        sample_ids: List[str],
        count: int,
        metadata: Optional[Dict[str, Dict[str, Any]]]
    ) -> Tuple[List[str], Optional[Dict[str, int]]]:
        """Select representative/diverse samples."""
        # Without metadata, fall back to random
        if not metadata:
            return self._random_sample(sample_ids, count)

        # Simple diversity selection: spread across metadata values
        # This is a simplified version; could use k-medoids for better diversity
        selected = []
        remaining = set(sample_ids)

        # Collect all metadata keys
        all_keys = set()
        for sample_meta in metadata.values():
            all_keys.update(sample_meta.keys())

        # Select samples that cover diverse metadata values
        for key in all_keys:
            if len(selected) >= count:
                break

            # Get unique values for this key
            value_samples: Dict[str, List[str]] = {}
            for sample_id in remaining:
                value = str(metadata.get(sample_id, {}).get(key, "unknown"))
                if value not in value_samples:
                    value_samples[value] = []
                value_samples[value].append(sample_id)

            # Take one from each value
            for value, samples in value_samples.items():
                if len(selected) >= count:
                    break
                if samples:
                    sample = self.rng.choice(samples)
                    if sample not in selected:
                        selected.append(sample)
                        remaining.discard(sample)

        # Fill remaining with random
        if len(selected) < count:
            additional = self.rng.sample(
                list(remaining),
                min(count - len(selected), len(remaining))
            )
            selected.extend(additional)

        return selected, None


class ProgressiveTuningController:
    """
    Orchestrates progressive parameter tuning workflow.

    Flow:
    1. Create pilot subset using DataSampler
    2. Run pilot analysis with default/recommended parameters
    3. Collect metrics and estimate full run resources
    4. Optionally optimize parameters on pilot data
    5. Present results for user review
    6. Execute full run with optimized parameters
    """

    # Default parameter search spaces for common tools
    DEFAULT_PARAM_SPACES = {
        "star": {
            "threads": [4, 8, 16],
            "outSAMtype": ["BAM SortedByCoordinate", "BAM Unsorted"]
        },
        "hisat2": {
            "threads": [4, 8, 16]
        },
        "bwa": {
            "threads": [4, 8, 16]
        },
        "salmon": {
            "threads": [4, 8, 16],
            "validateMappings": [True, False]
        },
        "featurecounts": {
            "threads": [4, 8, 16],
            "minOverlap": [1, 10],
            "fracOverlap": [0, 0.5]
        }
    }

    def __init__(
        self,
        config: TuningConfig = None,
        results_dir: str = None
    ):
        """
        Initialize controller.

        Args:
            config: Default tuning configuration
            results_dir: Directory to store pilot results
        """
        self.config = config or TuningConfig()
        self.sampler = DataSampler()
        self.results_dir = Path(results_dir) if results_dir else Path("/tmp/biomate_pilots")
        self.results_dir.mkdir(parents=True, exist_ok=True)

        self._active_pilots: Dict[str, PilotResult] = {}

    def calculate_pilot_size(
        self,
        total_size: int,
        config: TuningConfig = None
    ) -> int:
        """
        Calculate the number of samples for a pilot run.

        Args:
            total_size: Total number of samples
            config: Tuning configuration (uses default if None)

        Returns:
            Number of samples for pilot
        """
        config = config or self.config
        target = int(total_size * config.pilot_fraction)
        target = max(config.min_pilot_samples, target)
        target = min(config.max_pilot_samples, target, total_size)
        return target

    def create_pilot_subset(
        self,
        sample_ids: List[str],
        config: TuningConfig = None,
        metadata: Optional[Dict[str, Dict[str, Any]]] = None
    ) -> SamplingReport:
        """
        Create representative subset for pilot run.

        Args:
            sample_ids: All sample identifiers
            config: Tuning configuration (uses default if None)
            metadata: Optional sample metadata for stratified sampling

        Returns:
            SamplingReport with selected samples
        """
        config = config or self.config
        return self.sampler.sample(sample_ids, config, metadata)

    def start_pilot(
        self,
        workflow_id: str,
        sample_ids: List[str],
        config: TuningConfig = None,
        metadata: Optional[Dict[str, Dict[str, Any]]] = None,
        initial_parameters: Optional[Dict[str, Any]] = None
    ) -> PilotResult:
        """
        Start a pilot run.

        Args:
            workflow_id: Workflow to run
            sample_ids: All available sample IDs
            config: Tuning configuration
            metadata: Sample metadata for stratified sampling
            initial_parameters: Starting parameters (uses defaults if None)

        Returns:
            PilotResult with pilot_id for tracking
        """
        import uuid
        config = config or self.config

        # Create pilot subset
        sampling_report = self.create_pilot_subset(sample_ids, config, metadata)

        pilot_id = f"pilot_{uuid.uuid4().hex[:8]}"

        pilot_result = PilotResult(
            pilot_id=pilot_id,
            workflow_id=workflow_id,
            status="running",
            config=config,
            sampling_report=sampling_report,
            parameters_used=initial_parameters or {},
            started_at=datetime.now().isoformat()
        )

        self._active_pilots[pilot_id] = pilot_result

        # Save to disk
        self._save_pilot_result(pilot_result)

        log.info(f"Started pilot {pilot_id} with {sampling_report.selected_samples} samples")

        return pilot_result

    def complete_pilot(
        self,
        pilot_id: str,
        metrics: PilotMetrics,
        success: bool = True,
        error_message: str = None
    ) -> PilotResult:
        """
        Mark pilot as complete and record metrics.

        Args:
            pilot_id: Pilot identifier
            metrics: Collected metrics
            success: Whether pilot succeeded
            error_message: Error message if failed

        Returns:
            Updated PilotResult
        """
        if pilot_id not in self._active_pilots:
            # Try to load from disk
            pilot = self._load_pilot_result(pilot_id)
            if not pilot:
                raise ValueError(f"Unknown pilot: {pilot_id}")
        else:
            pilot = self._active_pilots[pilot_id]

        pilot.status = "complete" if success else "failed"
        pilot.completed_at = datetime.now().isoformat()
        pilot.metrics = metrics
        pilot.error_message = error_message

        self._save_pilot_result(pilot)
        log.info(f"Completed pilot {pilot_id}: {pilot.status}")

        return pilot

    def estimate_full_run(
        self,
        pilot_result: Any,
        full_size: int = None,
        cost_per_hour_usd: float = 0.50
    ) -> Dict[str, Any]:
        """
        Estimate resources for full dataset based on pilot.

        Args:
            pilot_result: Completed pilot result (PilotResult or simple dict/object)
            full_size: Number of samples in full dataset (optional, inferred from pilot_result if possible)
            cost_per_hour_usd: Cost per compute hour

        Returns:
            Dictionary with estimated resources
        """
        # Handle simple object with direct attributes (for testing)
        if hasattr(pilot_result, 'runtime_seconds') and hasattr(pilot_result, 'samples_used'):
            pilot_samples = pilot_result.samples_used
            pilot_runtime = pilot_result.runtime_seconds
            pilot_memory = getattr(pilot_result, 'peak_memory_gb', 1.0)
            full_sample_count = full_size or getattr(pilot_result, 'total_samples', pilot_samples * 10)
        elif hasattr(pilot_result, 'metrics') and pilot_result.metrics:
            pilot_samples = pilot_result.sampling_report.selected_samples
            pilot_runtime = pilot_result.metrics.runtime_seconds
            pilot_memory = pilot_result.metrics.peak_memory_gb
            full_sample_count = full_size or pilot_result.sampling_report.total_samples
        else:
            raise ValueError("Pilot has no metrics - cannot estimate full run")

        scaling_factor = full_sample_count / pilot_samples

        # Estimate runtime (often sublinear scaling)
        # Use sqrt for sublinear scaling assumption
        runtime_scaling = scaling_factor ** 0.85  # Slightly sublinear
        estimated_runtime = pilot_runtime * runtime_scaling

        # Memory often doesn't scale linearly with samples
        memory_scaling = 1 + (scaling_factor - 1) * 0.3  # Modest memory increase
        estimated_memory = pilot_memory * memory_scaling

        # Calculate cost
        hours = estimated_runtime / 3600
        estimated_cost = hours * cost_per_hour_usd

        # Format runtime display
        if estimated_runtime < 60:
            runtime_display = f"{int(estimated_runtime)} seconds"
        elif estimated_runtime < 3600:
            runtime_display = f"{int(estimated_runtime / 60)} minutes"
        else:
            hours_part = int(estimated_runtime / 3600)
            mins_part = int((estimated_runtime % 3600) / 60)
            runtime_display = f"{hours_part} hours {mins_part} minutes"

        # Return as dict for flexibility
        return {
            "estimated_runtime_seconds": estimated_runtime,
            "estimated_runtime_display": runtime_display,
            "estimated_memory_gb": estimated_memory,
            "estimated_cost_usd": round(estimated_cost, 2),
            "confidence": 0.8,
            "scaling_factors": {
                "sample_ratio": scaling_factor,
                "runtime_scaling": runtime_scaling,
                "memory_scaling": memory_scaling
            }
        }

    def optimize_parameters(
        self,
        pilot_result: PilotResult,
        param_space: Optional[Dict[str, List[Any]]] = None,
        workflow_executor: callable = None
    ) -> OptimizationResult:
        """
        Optimize parameters on pilot data.

        Args:
            pilot_result: Completed pilot result
            param_space: Parameter search space
            workflow_executor: Function to execute workflow with parameters

        Returns:
            OptimizationResult with best parameters
        """
        if not pilot_result.metrics:
            raise ValueError("Pilot must be complete before optimization")

        config = pilot_result.config
        baseline_params = pilot_result.parameters_used
        baseline_metrics = pilot_result.metrics

        # Get default param space for tools in workflow
        if not param_space:
            param_space = self._get_default_param_space(pilot_result.workflow_id)

        if not param_space:
            # No parameters to optimize
            return OptimizationResult(
                best_parameters=baseline_params,
                recommendations=[],
                iterations_run=0,
                metric_improvement=0.0
            )

        # Generate parameter combinations
        combinations = self._generate_param_combinations(
            param_space,
            config.optimization_budget
        )

        comparison_results = []
        best_params = baseline_params.copy()
        best_score = self._calculate_score(baseline_metrics, config.optimization_metric)

        iterations = 0
        for params in combinations:
            if iterations >= config.optimization_budget:
                break

            # Execute with new parameters (if executor provided)
            if workflow_executor:
                try:
                    test_params = baseline_params.copy()
                    test_params.update(params)

                    # Run workflow and collect metrics
                    metrics = workflow_executor(
                        pilot_result.workflow_id,
                        pilot_result.sampling_report.sample_ids,
                        test_params
                    )

                    score = self._calculate_score(metrics, config.optimization_metric)

                    comparison_results.append({
                        "parameters": params,
                        "metrics": metrics.to_dict(),
                        "score": score
                    })

                    if score > best_score:
                        best_score = score
                        best_params = test_params

                    iterations += 1

                except Exception as e:
                    log.warning(f"Optimization iteration failed: {e}")
                    continue

        # Generate recommendations
        recommendations = self._generate_recommendations(
            baseline_params, best_params, baseline_metrics, best_score
        )

        improvement = ((best_score / self._calculate_score(baseline_metrics, config.optimization_metric)) - 1) * 100

        return OptimizationResult(
            best_parameters=best_params,
            recommendations=recommendations,
            iterations_run=iterations,
            metric_improvement=improvement,
            comparison_results=comparison_results
        )

    def _get_default_param_space(self, workflow_id: str) -> Dict[str, List[Any]]:
        """Get default parameter space for workflow tools."""
        # In practice, this would parse the workflow to identify tools
        # and return relevant parameter spaces
        param_space = {}
        for tool, params in self.DEFAULT_PARAM_SPACES.items():
            if tool in workflow_id.lower():
                param_space.update(params)
        return param_space

    def _generate_param_combinations(
        self,
        param_space: Dict[str, List[Any]],
        max_combinations: int
    ) -> List[Dict[str, Any]]:
        """Generate parameter combinations for testing."""
        import itertools

        # Get all parameter names and values
        param_names = list(param_space.keys())
        param_values = list(param_space.values())

        # Generate all combinations
        all_combos = list(itertools.product(*param_values))

        # Convert to dicts
        combinations = [
            dict(zip(param_names, combo))
            for combo in all_combos
        ]

        # Limit to max_combinations
        if len(combinations) > max_combinations:
            import random
            combinations = random.sample(combinations, max_combinations)

        return combinations

    def _calculate_score(
        self,
        metrics: PilotMetrics,
        optimization_metric: OptimizationMetric
    ) -> float:
        """Calculate optimization score from metrics."""
        if optimization_metric == OptimizationMetric.RUNTIME:
            # Lower runtime = higher score
            return 1.0 / (metrics.runtime_seconds + 1)
        elif optimization_metric == OptimizationMetric.MEMORY:
            # Lower memory = higher score
            return 1.0 / (metrics.peak_memory_gb + 1)
        elif optimization_metric == OptimizationMetric.QUALITY:
            # Higher quality metrics = higher score
            if metrics.quality_metrics:
                return sum(metrics.quality_metrics.values()) / len(metrics.quality_metrics)
            return 0.5
        else:  # BALANCED
            runtime_score = 1.0 / (metrics.runtime_seconds + 1)
            memory_score = 1.0 / (metrics.peak_memory_gb + 1)
            quality_score = 0.5
            if metrics.quality_metrics:
                quality_score = sum(metrics.quality_metrics.values()) / len(metrics.quality_metrics)
            return (runtime_score + memory_score + quality_score) / 3

    def _generate_recommendations(
        self,
        baseline_params: Dict[str, Any],
        best_params: Dict[str, Any],
        baseline_metrics: PilotMetrics,
        best_score: float
    ) -> List[ParameterRecommendation]:
        """Generate parameter recommendations from optimization."""
        recommendations = []

        for param_name, best_value in best_params.items():
            baseline_value = baseline_params.get(param_name)

            if baseline_value != best_value:
                # Calculate improvement (simplified)
                improvement = 10.0  # Placeholder - real calculation depends on metric

                recommendations.append(ParameterRecommendation(
                    parameter_name=param_name,
                    recommended_value=best_value,
                    current_value=baseline_value,
                    improvement_percent=improvement,
                    confidence=0.75,
                    reason=f"Optimization found {best_value} performs better than {baseline_value}"
                ))

        return recommendations

    def _save_pilot_result(self, pilot: PilotResult):
        """Save pilot result to disk."""
        path = self.results_dir / f"{pilot.pilot_id}.json"
        with open(path, "w") as f:
            json.dump(pilot.to_dict(), f, indent=2)

    def _load_pilot_result(self, pilot_id: str) -> Optional[PilotResult]:
        """Load pilot result from disk."""
        path = self.results_dir / f"{pilot_id}.json"
        if not path.exists():
            return None

        with open(path) as f:
            data = json.load(f)

        # Reconstruct PilotResult
        return PilotResult(
            pilot_id=data["pilot_id"],
            workflow_id=data["workflow_id"],
            status=data["status"],
            config=TuningConfig.from_dict(data["config"]),
            sampling_report=SamplingReport(**data["sampling_report"]),
            metrics=PilotMetrics(**data["metrics"]) if data.get("metrics") else None,
            parameters_used=data.get("parameters_used", {}),
            started_at=data.get("started_at", ""),
            completed_at=data.get("completed_at"),
            error_message=data.get("error_message")
        )

    def get_pilot_status(self, pilot_id: str) -> Optional[PilotResult]:
        """Get current status of a pilot."""
        if pilot_id in self._active_pilots:
            return self._active_pilots[pilot_id]
        return self._load_pilot_result(pilot_id)

    def list_pilots(self, workflow_id: str = None) -> List[PilotResult]:
        """List all pilots, optionally filtered by workflow."""
        pilots = []

        for path in self.results_dir.glob("pilot_*.json"):
            pilot = self._load_pilot_result(path.stem)
            if pilot:
                if workflow_id is None or pilot.workflow_id == workflow_id:
                    pilots.append(pilot)

        return sorted(pilots, key=lambda p: p.started_at, reverse=True)


# Workflow-type specific configurations
WORKFLOW_TUNING_CONFIGS = {
    "rna_seq_de": TuningConfig(
        pilot_fraction=0.15,
        min_pilot_samples=6,  # Need enough for statistical power
        sampling_strategy=SamplingStrategy.STRATIFIED,
        strata_column="condition"
    ),
    "variant_calling": TuningConfig(
        pilot_fraction=0.05,
        sampling_strategy=SamplingStrategy.CHROMOSOME
    ),
    "metagenomics": TuningConfig(
        pilot_fraction=0.1,
        sampling_strategy=SamplingStrategy.RANDOM
    ),
    "single_cell": TuningConfig(
        pilot_fraction=0.05,  # Single-cell has many cells
        max_pilot_samples=1000
    ),
    "proteomics": TuningConfig(
        pilot_fraction=0.2,
        sampling_strategy=SamplingStrategy.STRATIFIED
    )
}


def get_tuning_config(workflow_type: str) -> TuningConfig:
    """Get appropriate tuning configuration for workflow type."""
    return WORKFLOW_TUNING_CONFIGS.get(workflow_type, TuningConfig())
