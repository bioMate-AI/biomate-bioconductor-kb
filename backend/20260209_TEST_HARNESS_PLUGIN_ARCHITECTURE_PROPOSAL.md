# Test Harness Plugin Architecture Proposal

**Date**: 2026-02-09
**Status**: Proposal
**Related**: Pilot Analysis Plugin Architecture (implemented)

## Executive Summary

Based on successful implementation of domain plugin architecture for pilot analysis, we propose applying the same pattern to the test harness for parameter optimization. This provides clear organization by domain, enabling domain experts to tune evaluation metrics and search spaces independently.

## Background

### User Question

> "Previously we are discussing about adding a plugin for each domain, do you think we still should do that to make it more clear and convenient for tuning?"
>
> "I mean, for the test harness. As for the pilot analysis registry, make it clear for different domain, or different data types are also important"

### Current Situation

The pilot analysis framework was successfully refactored into a domain plugin architecture:
- **7 domain plugins**: genomics, single_cell, bioimaging, cryo_em, molecular_biology, pharmacology, biochemistry
- **20 analyzers** organized by domain
- **Clear separation** of concerns and dependencies
- **Easy extensibility** - add new analyzers without touching other domains

### The Same Need Exists for Test Harness

The test harness faces similar challenges:
1. **Different domains need different metrics** (NSC/RSC for ChIP-seq vs FSC for cryo-EM)
2. **Parameter search spaces vary by domain** (genomics vs imaging)
3. **Domain experts should tune their own evaluators** without affecting others
4. **Dependencies differ** (genomics tools vs cryo-EM tools)

## Proposed Architecture

### Directory Structure

```
backend/lib/galaxy/ai/test_harness/
├── __init__.py              # TestHarnessPluginManager
├── base.py                  # Base classes (TestHarnessPlugin, EvaluationSpec)
├── executor.py              # Executes workflows and evaluates results
├── README.md                # Documentation
└── plugins/
    ├── __init__.py
    ├── genomics.py          # ChIP-seq, RNA-seq, DNA-seq evaluators
    ├── single_cell.py       # scRNA-seq evaluators
    ├── bioimaging.py        # Image registration evaluators
    ├── cryo_em.py           # SPA/ET evaluators
    ├── molecular_biology.py # Cloning/primer evaluators
    ├── pharmacology.py      # Docking/ADMET evaluators
    └── biochemistry.py      # Enzyme kinetics evaluators
```

### Base Classes

#### 1. EvaluationSpec

Defines how to evaluate a workflow execution:

```python
@dataclass
class EvaluationSpec:
    """Specification for evaluating a workflow execution."""

    name: str                           # e.g., "chipseq_peak_calling_quality"
    domain: str                         # e.g., "genomics"
    description: str                    # What this evaluator measures

    # Metrics to extract from outputs
    metrics: Dict[str, MetricDefinition]

    # How to score the execution (0-100)
    scoring_function: Callable[[Dict], float]

    # Thresholds for pass/fail
    quality_thresholds: Dict[str, Any]

    # Which output files to analyze
    output_files: List[str]

    # Optional: ground truth for comparison
    ground_truth_required: bool = False


@dataclass
class MetricDefinition:
    """Definition of a single evaluation metric."""

    name: str                   # e.g., "nsc_score"
    description: str            # What this metric measures
    extractor: Callable         # Function to extract from output
    higher_is_better: bool      # Direction of optimization
    min_acceptable: Optional[float] = None
    target_range: Optional[Tuple[float, float]] = None
```

#### 2. ParameterSearchSpace

Defines valid parameter ranges for optimization:

```python
@dataclass
class ParameterSearchSpace:
    """Search space for a tool parameter."""

    parameter_name: str
    search_type: str            # "grid", "random", "bayesian"

    # For continuous parameters
    min_value: Optional[float] = None
    max_value: Optional[float] = None
    step: Optional[float] = None

    # For discrete parameters
    discrete_values: Optional[List[Any]] = None

    # For conditional parameters
    depends_on: Optional[Dict[str, Any]] = None

    # Priority for optimization
    priority: int = 1  # 1=high, 3=low
```

#### 3. TestHarnessPlugin

Base class for domain-specific plugins:

```python
class TestHarnessPlugin(ABC):
    """Base class for domain-specific test harness plugins."""

    @property
    @abstractmethod
    def domain_name(self) -> str:
        """Return domain name (e.g., 'genomics')."""
        pass

    @property
    @abstractmethod
    def evaluators(self) -> Dict[str, EvaluationSpec]:
        """Return dict of evaluator_name -> EvaluationSpec."""
        pass

    @property
    @abstractmethod
    def search_spaces(self) -> Dict[str, Dict[str, ParameterSearchSpace]]:
        """
        Return parameter search spaces for this domain's tools.

        Format: {tool_id: {param_name: ParameterSearchSpace}}
        """
        pass

    @property
    def dependencies(self) -> List[str]:
        """Tools required for evaluation in this domain."""
        return []

    def evaluate_workflow(
        self,
        workflow_id: str,
        invocation_id: str,
        parameters: Dict[str, Any],
        outputs: Dict[str, Path]
    ) -> EvaluationResult:
        """
        Evaluate a workflow execution.

        Args:
            workflow_id: Galaxy workflow ID
            invocation_id: Galaxy invocation ID
            parameters: Parameters used for this run
            outputs: Dict mapping output names to file paths

        Returns:
            EvaluationResult with metrics and score
        """
        pass
```

### Example: Genomics Plugin

```python
# backend/lib/galaxy/ai/test_harness/plugins/genomics.py

class GenomicsTestHarnessPlugin(TestHarnessPlugin):
    """Test harness plugin for genomics workflows."""

    @property
    def domain_name(self) -> str:
        return "genomics"

    @property
    def dependencies(self) -> list:
        return ["phantompeakqualtools", "deeptools", "bedtools"]

    @property
    def evaluators(self) -> Dict[str, EvaluationSpec]:
        return {
            "chipseq_peak_calling_quality": EvaluationSpec(
                name="chipseq_peak_calling_quality",
                domain="genomics",
                description="Evaluate ChIP-seq peak calling quality using NSC/RSC",
                metrics={
                    "nsc": MetricDefinition(
                        name="nsc",
                        description="Normalized strand cross-correlation",
                        extractor=self._extract_nsc,
                        higher_is_better=True,
                        min_acceptable=1.05,
                        target_range=(1.1, 1.3)
                    ),
                    "rsc": MetricDefinition(
                        name="rsc",
                        description="Relative strand cross-correlation",
                        extractor=self._extract_rsc,
                        higher_is_better=True,
                        min_acceptable=1.0,
                        target_range=(1.2, 2.0)
                    ),
                    "num_peaks": MetricDefinition(
                        name="num_peaks",
                        description="Number of peaks called",
                        extractor=self._count_peaks,
                        higher_is_better=None,  # Context-dependent
                        target_range=(1000, 50000)
                    ),
                    "frip": MetricDefinition(
                        name="frip",
                        description="Fraction of reads in peaks",
                        extractor=self._calculate_frip,
                        higher_is_better=True,
                        min_acceptable=0.01,
                        target_range=(0.05, 0.3)
                    )
                },
                scoring_function=self._score_chipseq_quality,
                quality_thresholds={
                    "excellent": {"nsc": 1.2, "rsc": 1.5, "frip": 0.1},
                    "good": {"nsc": 1.1, "rsc": 1.2, "frip": 0.05},
                    "acceptable": {"nsc": 1.05, "rsc": 1.0, "frip": 0.01}
                },
                output_files=["peaks.bed", "alignment.bam"]
            ),

            "rnaseq_alignment_quality": EvaluationSpec(
                name="rnaseq_alignment_quality",
                domain="genomics",
                description="Evaluate RNA-seq alignment quality",
                metrics={
                    "mapping_rate": MetricDefinition(
                        name="mapping_rate",
                        description="Percentage of reads mapped",
                        extractor=self._extract_mapping_rate,
                        higher_is_better=True,
                        min_acceptable=70.0,
                        target_range=(85.0, 95.0)
                    ),
                    "uniquely_mapped": MetricDefinition(
                        name="uniquely_mapped",
                        description="Percentage uniquely mapped",
                        extractor=self._extract_unique_mapping,
                        higher_is_better=True,
                        min_acceptable=60.0,
                        target_range=(75.0, 90.0)
                    )
                },
                scoring_function=self._score_rnaseq_quality,
                quality_thresholds={
                    "excellent": {"mapping_rate": 90, "uniquely_mapped": 80},
                    "good": {"mapping_rate": 85, "uniquely_mapped": 75},
                    "acceptable": {"mapping_rate": 70, "uniquely_mapped": 60}
                },
                output_files=["aligned.bam", "alignment_log.txt"]
            )
        }

    @property
    def search_spaces(self) -> Dict[str, Dict[str, ParameterSearchSpace]]:
        """Define parameter search spaces for genomics tools."""
        return {
            "biomni/genomics/perform_chipseq_peak_calling_with_macs2": {
                "extsize": ParameterSearchSpace(
                    parameter_name="extsize",
                    search_type="grid",
                    min_value=100,
                    max_value=400,
                    step=50,
                    priority=1  # High priority - affects quality significantly
                ),
                "qvalue": ParameterSearchSpace(
                    parameter_name="qvalue",
                    search_type="grid",
                    discrete_values=[0.001, 0.01, 0.05, 0.1],
                    priority=1
                ),
                "bandwidth": ParameterSearchSpace(
                    parameter_name="bandwidth",
                    search_type="grid",
                    min_value=150,
                    max_value=450,
                    step=100,
                    priority=2  # Medium priority
                )
            },

            "biomni/genomics/align_rnaseq_reads_with_star": {
                "outFilterMismatchNmax": ParameterSearchSpace(
                    parameter_name="outFilterMismatchNmax",
                    search_type="grid",
                    discrete_values=[2, 5, 10, 15],
                    priority=2
                ),
                "outFilterMultimapNmax": ParameterSearchSpace(
                    parameter_name="outFilterMultimapNmax",
                    search_type="grid",
                    discrete_values=[1, 10, 20, 50],
                    priority=1
                )
            }
        }

    def _extract_nsc(self, outputs: Dict[str, Path]) -> float:
        """Extract NSC from phantompeakqualtools output."""
        # Implementation here
        pass

    def _score_chipseq_quality(self, metrics: Dict[str, float]) -> float:
        """
        Score ChIP-seq quality (0-100).

        Weighted combination of NSC, RSC, FRiP, and peak count.
        """
        score = 0.0

        # NSC component (30 points)
        nsc = metrics.get("nsc", 0)
        if nsc >= 1.2:
            score += 30
        elif nsc >= 1.1:
            score += 20
        elif nsc >= 1.05:
            score += 10

        # RSC component (30 points)
        rsc = metrics.get("rsc", 0)
        if rsc >= 1.5:
            score += 30
        elif rsc >= 1.2:
            score += 20
        elif rsc >= 1.0:
            score += 10

        # FRiP component (30 points)
        frip = metrics.get("frip", 0)
        if frip >= 0.1:
            score += 30
        elif frip >= 0.05:
            score += 20
        elif frip >= 0.01:
            score += 10

        # Peak count component (10 points)
        num_peaks = metrics.get("num_peaks", 0)
        if 5000 <= num_peaks <= 30000:
            score += 10
        elif 1000 <= num_peaks <= 50000:
            score += 5

        return score
```

### Example: Cryo-EM Plugin

```python
# backend/lib/galaxy/ai/test_harness/plugins/cryo_em.py

class CryoEMTestHarnessPlugin(TestHarnessPlugin):
    """Test harness plugin for cryo-EM workflows."""

    @property
    def domain_name(self) -> str:
        return "cryo_em"

    @property
    def evaluators(self) -> Dict[str, EvaluationSpec]:
        return {
            "spa_reconstruction_quality": EvaluationSpec(
                name="spa_reconstruction_quality",
                domain="cryo_em",
                description="Evaluate SPA reconstruction quality using FSC",
                metrics={
                    "fsc_resolution": MetricDefinition(
                        name="fsc_resolution",
                        description="Resolution at FSC=0.143",
                        extractor=self._extract_fsc_resolution,
                        higher_is_better=False,  # Lower Å = better
                        target_range=(2.0, 4.0)  # Typical range for high-quality
                    ),
                    "particle_count": MetricDefinition(
                        name="particle_count",
                        description="Number of particles in final reconstruction",
                        extractor=self._extract_particle_count,
                        higher_is_better=True,
                        min_acceptable=10000
                    ),
                    "angular_distribution_efficiency": MetricDefinition(
                        name="angular_distribution_efficiency",
                        description="Efficiency of angular sampling",
                        extractor=self._calculate_angular_efficiency,
                        higher_is_better=True,
                        min_acceptable=0.7,
                        target_range=(0.8, 1.0)
                    )
                },
                scoring_function=self._score_spa_quality,
                quality_thresholds={
                    "excellent": {"fsc_resolution": 3.0, "efficiency": 0.9},
                    "good": {"fsc_resolution": 4.0, "efficiency": 0.8},
                    "acceptable": {"fsc_resolution": 6.0, "efficiency": 0.7}
                },
                output_files=["final_map.mrc", "fsc_curve.txt", "angular_distribution.txt"],
                ground_truth_required=False
            )
        }

    @property
    def search_spaces(self) -> Dict[str, Dict[str, ParameterSearchSpace]]:
        return {
            "biomni/cryo_em/ab_initio_reconstruction": {
                "num_classes": ParameterSearchSpace(
                    parameter_name="num_classes",
                    search_type="grid",
                    discrete_values=[1, 2, 3, 4, 5],
                    priority=1
                )
            },
            "biomni/cryo_em/homogeneous_refinement": {
                "box_size": ParameterSearchSpace(
                    parameter_name="box_size",
                    search_type="grid",
                    discrete_values=[256, 384, 512],
                    priority=2
                )
            }
        }
```

### Plugin Manager

```python
# backend/lib/galaxy/ai/test_harness/__init__.py

class TestHarnessPluginManager:
    """Central manager for test harness plugins."""

    def __init__(self):
        self.plugins: Dict[str, TestHarnessPlugin] = {}
        self._register_plugins()

    def _register_plugins(self):
        """Load all domain plugins."""
        from .plugins import (
            GenomicsTestHarnessPlugin,
            SingleCellTestHarnessPlugin,
            CryoEMTestHarnessPlugin,
            # ... other plugins
        )

        for plugin_class in [GenomicsTestHarnessPlugin, ...]:
            plugin = plugin_class()
            self.plugins[plugin.domain_name] = plugin

    def get_evaluator(self, domain: str, evaluator_name: str) -> Optional[EvaluationSpec]:
        """Get specific evaluator from a domain."""
        if domain in self.plugins:
            return self.plugins[domain].evaluators.get(evaluator_name)
        return None

    def get_search_space(self, tool_id: str) -> Dict[str, ParameterSearchSpace]:
        """
        Get parameter search space for a tool (searches all domains).

        Returns dict of parameter_name -> ParameterSearchSpace.
        """
        for plugin in self.plugins.values():
            if tool_id in plugin.search_spaces:
                return plugin.search_spaces[tool_id]
        return {}

    def run_optimization(
        self,
        workflow_id: str,
        domain: str,
        evaluator_name: str,
        num_iterations: int = 10
    ) -> OptimizationResult:
        """
        Run parameter optimization for a workflow.

        1. Get evaluator for quality assessment
        2. Get search spaces for parameters
        3. Run Bayesian optimization
        4. Return optimal parameters
        """
        pass
```

## Benefits

### 1. **Clear Organization**
- Each domain's evaluators in dedicated file
- Easy to find relevant metrics and search spaces
- Domain experts focus on their area

### 2. **Independent Tuning**
- Adjust quality thresholds per domain
- Modify scoring functions without affecting other domains
- Update search spaces based on empirical results

### 3. **Extensibility**
- Add new domains easily
- Add new evaluators to existing domains
- No central registry to maintain

### 4. **Dependency Management**
- Each plugin specifies required evaluation tools
- Check availability before running optimization
- Graceful degradation if tools missing

### 5. **Testing**
- Test each domain's evaluators independently
- Mock outputs for faster testing
- Verify scoring functions

### 6. **Parallel with Pilot Analysis**
- Same architecture pattern
- Easy to understand and maintain
- Consistent developer experience

## Integration with 4-Tier Parameter Inference

```
User Query
    ↓
Tier 1: Context Requirements DB
    ↓
Tier 2: LLM Progressive Dialogue
    ↓
Tier 3: Pilot Analysis (domain plugins) ← Already implemented
    ↓
Tier 4: Test Harness (domain plugins) ← This proposal
    ↓
Optimal Parameters
```

## Implementation Plan

### Phase 1: Base Framework (Week 1)
- [ ] Create base classes (TestHarnessPlugin, EvaluationSpec, ParameterSearchSpace)
- [ ] Implement PluginManager
- [ ] Create executor framework
- [ ] Write comprehensive tests

### Phase 2: Domain Plugins (Week 2-3)
- [ ] Genomics plugin (ChIP-seq, RNA-seq evaluators)
- [ ] Cryo-EM plugin (SPA quality evaluators)
- [ ] Single-cell plugin (integration quality evaluators)
- [ ] Bioimaging plugin (registration quality evaluators)

### Phase 3: Optimization Engine (Week 4)
- [ ] Bayesian optimization integration
- [ ] Grid search for discrete parameters
- [ ] Result caching and reuse
- [ ] Progress tracking

### Phase 4: Integration (Week 5)
- [ ] Connect to pilot analysis results
- [ ] API endpoints for frontend
- [ ] Database for optimization history
- [ ] Reporting and visualization

## Recommendation

**YES, we should implement domain plugins for the test harness.**

**Rationale:**
1. **Proven success** with pilot analysis plugin architecture
2. **Clear need** for domain-specific tuning and metrics
3. **Scalability** - easy to extend as we add more domains
4. **Maintainability** - domain experts can own their evaluators
5. **Consistency** - same pattern across pilot analysis and test harness

## Next Steps

1. **User approval** of this proposal
2. **Create base framework** (base.py, PluginManager)
3. **Implement genomics plugin** as reference (most mature domain)
4. **Extend to other domains** following the pattern
5. **Integrate with existing parameter inference system**

## Questions for Discussion

1. Should we support cross-domain evaluators (e.g., general alignment quality)?
2. How to handle multi-step workflows that span domains?
3. Should optimization results be shared across users (privacy considerations)?
4. Integration with external benchmark datasets?

---

**Author**: Claude Code
**Reviewer**: [To be assigned]
**Approval**: [Pending]
