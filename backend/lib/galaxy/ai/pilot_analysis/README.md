# Pilot Analysis Plugin Architecture

## Overview

The Pilot Analysis framework provides a domain plugin architecture for quick data characterization that informs intelligent parameter inference. Each scientific domain (genomics, cryo-EM, etc.) implements a plugin with domain-specific analyzers.

## Architecture

```
backend/lib/galaxy/ai/pilot_analysis/
├── __init__.py              # PluginManager - central coordination
├── base.py                  # Base classes (PilotAnalysisPlugin, AnalyzerSpec)
├── registry.py              # Legacy monolithic format (deprecated)
└── plugins/
    ├── __init__.py
    ├── genomics.py          # Genomics analyzers (6 analyzers)
    ├── single_cell.py       # Single-cell RNA-seq analyzers (3 analyzers)
    ├── bioimaging.py        # Medical imaging analyzers (2 analyzers)
    ├── cryo_em.py           # Cryo-EM analyzers (3 analyzers)
    ├── molecular_biology.py # Cloning/primer analyzers (3 analyzers)
    ├── pharmacology.py      # Drug discovery analyzers (2 analyzers)
    └── biochemistry.py      # Enzyme kinetics analyzers (1 analyzer)
```

## Key Components

### 1. AnalyzerSpec

Defines a single pilot analyzer with all its metadata:

```python
AnalyzerSpec(
    name="estimate_fragment_size",
    category="genomics",
    description="Estimate DNA fragment size from BAM file",
    input_type="bam",
    tool="samtools_stats",
    command_template="samtools stats {input_file} | grep 'insert size average'",
    extract="insert_size_average",
    runtime_estimate="~30s per 10M reads",
    max_runtime_seconds=300,
    sample_strategy="first_10M_reads",
    fallback=200,
    output_type="integer",
    units="bp",
    typical_range=[100, 500]
)
```

### 2. PilotAnalysisPlugin

Base class for domain-specific plugins. Each domain implements this:

```python
class GenomicsPilotPlugin(PilotAnalysisPlugin):
    @property
    def domain_name(self) -> str:
        return "genomics"

    @property
    def dependencies(self) -> list:
        return ["samtools", "fastqc", "phantompeakqualtools"]

    @property
    def analyzers(self) -> Dict[str, AnalyzerSpec]:
        return {
            "estimate_fragment_size": AnalyzerSpec(...),
            "estimate_fragment_shift": AnalyzerSpec(...),
            # ... more analyzers
        }
```

### 3. PilotAnalysisPluginManager

Central registry that coordinates all domain plugins:

```python
from lib.galaxy.ai.pilot_analysis import get_pilot_manager

manager = get_pilot_manager()

# Get specific analyzer (searches all domains)
analyzer = manager.get_analyzer("estimate_fragment_size")

# Get all analyzers for a domain
genomics_analyzers = manager.get_domain_analyzers("genomics")

# Find quick analyzers (<30s runtime)
quick = manager.get_quick_analyzers(max_runtime=30)

# Check dependencies
deps = manager.check_domain_dependencies("cryo_em")
```

## Benefits of Plugin Architecture

### 1. **Clear Organization by Domain**
   - Each domain's analyzers are in a dedicated file
   - Easy to find and understand what's available
   - Domain experts can focus on their area

### 2. **Independent Tuning**
   - Adjust thresholds/parameters per domain
   - Update dependencies without affecting other domains
   - Test domains in isolation

### 3. **Extensibility**
   - Add new domains by creating a new plugin
   - Add analyzers to existing domains easily
   - No need to modify central registry

### 4. **Dependency Management**
   - Each plugin specifies its required tools
   - Can check availability before using analyzers
   - Graceful degradation if tools missing

### 5. **Testing**
   - Test each domain's analyzers independently
   - Mock dependencies per domain
   - Verify analyzer specifications

## Usage Examples

### Basic Usage

```python
from lib.galaxy.ai.pilot_analysis import get_pilot_manager

manager = get_pilot_manager()

# Get analyzer for ChIP-seq fragment size estimation
spec = manager.get_analyzer("estimate_fragment_size")

if spec:
    print(f"Tool: {spec.tool}")
    print(f"Runtime: {spec.runtime_estimate}")
    print(f"Command: {spec.command_template}")
```

### Find Appropriate Analyzer

```python
# User uploaded a BAM file - what can we analyze?
bam_analyzers = manager.get_analyzers_by_input_type("bam")

for item in bam_analyzers:
    print(f"{item['name']} ({item['domain']}): {item['spec'].description}")
```

### Check Dependencies Before Running

```python
# Before running cryo-EM analyzers, check dependencies
deps = manager.check_domain_dependencies("cryo_em")

if not all(deps.values()):
    missing = [tool for tool, available in deps.items() if not available]
    print(f"Missing tools: {', '.join(missing)}")
else:
    # Safe to run cryo-EM analyzers
    analyzer = manager.get_analyzer("estimate_particle_size_from_micrographs")
```

### Summary Report

```python
print(manager.summary())
```

Output:
```
Pilot Analysis Plugin Manager Summary
==================================================

Total analyzers: 23
Total domains: 7

  biochemistry         1 analyzers, 1 dependencies
  bioimaging           2 analyzers, 2 dependencies
  cryo_em              3 analyzers, 3 dependencies
  genomics             6 analyzers, 4 dependencies
  molecular_biology    3 analyzers, 3 dependencies
  pharmacology         2 analyzers, 2 dependencies
  single_cell          3 analyzers, 2 dependencies

Quick analyzers (<30s): 14
Quick analyzers (<60s): 20
```

## Adding a New Domain Plugin

1. **Create plugin file**: `plugins/your_domain.py`

```python
from typing import Dict
from ..base import PilotAnalysisPlugin, AnalyzerSpec

class YourDomainPilotPlugin(PilotAnalysisPlugin):
    @property
    def domain_name(self) -> str:
        return "your_domain"

    @property
    def dependencies(self) -> list:
        return ["tool1", "tool2"]

    @property
    def analyzers(self) -> Dict[str, AnalyzerSpec]:
        return {
            "your_analyzer": AnalyzerSpec(
                name="your_analyzer",
                category="your_domain",
                description="What this analyzer does",
                input_type="file_type",
                tool="tool_name",
                command_template="tool_command {input_file}",
                extract="field_to_extract",
                runtime_estimate="~10s",
                max_runtime_seconds=30,
                sample_strategy="full_file",
                fallback=None,
                output_type="string",
            )
        }
```

2. **Register in `plugins/__init__.py`**:

```python
from .your_domain import YourDomainPilotPlugin

__all__ = [..., "YourDomainPilotPlugin"]
```

3. **Register in main `__init__.py`**:

```python
from .plugins import YourDomainPilotPlugin

# In PilotAnalysisPluginManager._register_plugins():
plugin_classes = [
    ...,
    YourDomainPilotPlugin,
]
```

## Extending to Test Harness

This same plugin architecture can be applied to the test harness for parameter optimization:

```python
# Example: Test harness with domain plugins
class TestHarnessPlugin(ABC):
    @property
    def domain_name(self) -> str
        pass

    @property
    def evaluation_metrics(self) -> Dict[str, MetricSpec]:
        """Domain-specific metrics for parameter evaluation"""
        pass

    @property
    def parameter_search_spaces(self) -> Dict[str, SearchSpace]:
        """Domain-specific parameter search ranges"""
        pass

    def evaluate_workflow(self, params: Dict, outputs: Dict) -> float:
        """Score workflow execution with given parameters"""
        pass
```

Each domain would define:
- **Metrics**: How to evaluate success (e.g., NSC/RSC for ChIP-seq, FSC for cryo-EM)
- **Search spaces**: Valid parameter ranges for optimization
- **Evaluation logic**: How to score a workflow execution

This maintains the same benefits:
- Clear organization by domain
- Independent tuning of metrics and search spaces
- Domain experts can extend/modify their evaluators
- Test each domain's harness independently

## Integration with Parameter Inference

The pilot analysis framework integrates with the 4-tier parameter inference system:

1. **User Query** → Context Requirements DB
2. **LLM Dialogue** → Progressive question gathering
3. **Pilot Analysis** ← **This framework provides the analyzers**
4. **Test Harness** → Empirical parameter optimization

Example workflow:
```python
# User: "Call peaks from H3K27me3 ChIP-seq"

# Tier 1: Context requirements DB says we need fragment_size
context_req = get_context_requirements("perform_chipseq_peak_calling_with_macs2")
# → Need: antibody_target, fragment_size

# Tier 2: LLM extracts antibody_target="H3K27me3" from query

# Tier 3: Pilot analysis estimates fragment_size from BAM
manager = get_pilot_manager()
analyzer = manager.get_analyzer("estimate_fragment_size")
fragment_size = run_pilot_analyzer(analyzer, user_bam_file)
# → fragment_size = 247 bp

# Tier 4: Test harness has optimal extsize for H3K27me3
optimal_params = query_test_harness("macs2", {"mark": "H3K27me3"})
# → extsize = 200 (broad mark)

# Final parameters
params = {
    "peak_type": "broad",  # from context
    "fragment_size": 247,   # from pilot analysis
    "extsize": 200          # from test harness
}
```

## Current Status

- ✅ **Base architecture** implemented (base.py, PluginManager)
- ✅ **7 domain plugins** implemented (23 total analyzers)
- ✅ **Dependency checking** framework
- ⏳ **Executor framework** (next step - actually run the analyzers)
- ⏳ **Test harness plugins** (apply same architecture to parameter optimization)
- ⏳ **Integration with context gatherer** (use pilot results in parameter inference)

## Next Steps

1. Implement `PilotAnalysisExecutor` to actually run the analyzers
2. Create test harness plugin architecture following same pattern
3. Connect pilot analysis results to `ContextGatherer`
4. Build API endpoints for frontend integration
5. Implement caching for pilot analysis results
