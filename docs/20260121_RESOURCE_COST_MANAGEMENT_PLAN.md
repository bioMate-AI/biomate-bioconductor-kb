# Resource Management & Cost Estimation Plan for Biomate

**Date:** 2026-01-21
**Author:** Claude (AI Assistant)
**Status:** Draft for Team Discussion

---

## Executive Summary

This document surveys how Galaxy and Nextflow handle workflow resource requirements, cost estimation, and capacity management. It identifies gaps in biomate's current implementation and proposes a phased plan to enable:

1. **User cost transparency** - Users can see estimated costs before running workflows
2. **Resource validation** - Prevent workflows from exceeding available resources
3. **Business planning** - Track actual costs for pricing decisions
4. **Capacity planning** - Understand tool limits and output sizes

---

## 1. Survey: Galaxy Resource Management

### 1.1 Job Configuration (`backend/config/job_conf.yml`)

Galaxy uses YAML-based job configuration with:

```yaml
runners:
  local:
    load: galaxy.jobs.runners.local:LocalJobRunner
    workers: 4

execution:
  default: docker_local
  environments:
    docker_local:
      runner: local
      docker_enabled: true
      docker_auto_rm: true
      docker_net: host
      docker_default_container_id: biomate/biotools:arm64-v5

limits:
  - type: registered_user_concurrent_jobs
    value: 4
  - type: anonymous_user_concurrent_jobs
    value: 1
```

**Key Features:**
- Tool-to-destination mapping via regex patterns
- Concurrency limits per user type
- Docker container specifications

### 1.2 Job Metrics System

Galaxy tracks actual resource usage via plugin-based metrics:

| Metric Plugin | Metrics Collected | Source |
|---------------|-------------------|--------|
| **Core** | `galaxy_slots`, `galaxy_memory_mb`, `runtime_seconds`, `container_id` | `backend/lib/galaxy/job_metrics/instrumenters/core.py` |
| **CGroup** | `memory.peak`, `cpu.stat.usage_usec`, `memory.events.oom_kill` | `backend/lib/galaxy/job_metrics/instrumenters/cgroup.py` |
| **MemInfo** | `memtotal`, `swaptotal` | `backend/lib/galaxy/job_metrics/instrumenters/meminfo.py` |

**Database Tables:**
- `job_metric_numeric` - Stores decimal metrics (CPU time, memory bytes)
- `job_metric_text` - Stores text metrics (container ID, plugin names)

### 1.3 Tool Resource Specifications

**Current State:** Tool XML files document resources in `<help>` text only:

```xml
<!-- backend/tools/biomate_ai_tools/alphafold3.xml -->
<help><![CDATA[
**Hardware Requirements:**
- GPU Memory: ~80-100 GB (may work on NVIDIA GB10 with 120GB)
- Disk Space: ~100 GB for model weights
]]></help>
```

**Problem:** Not machine-readable, can't be used for:
- Pre-flight validation
- Cost estimation
- Automatic resource allocation

### 1.4 Cost/Billing System

**Current:** Subscription-only model via Stripe (`backend/config/auth_payment_config.yml.example`):
- 10-day free trial
- $20/month or $200/year
- No per-job cost tracking

---

## 2. Survey: Nextflow Resource Management

### 2.1 Process Labels with Resource Tiers

Nextflow uses a structured label system (`backend/nf-core-workflows/rnaseq/conf/base.config`):

```groovy
withLabel:process_single {
    cpus   = { 1                   }
    memory = { 6.GB * task.attempt }
    time   = { 4.h  * task.attempt }
}

withLabel:process_low {
    cpus   = { 2     * task.attempt }
    memory = { 12.GB * task.attempt }
    time   = { 4.h   * task.attempt }
}

withLabel:process_medium {
    cpus   = { 6     * task.attempt }
    memory = { 36.GB * task.attempt }
    time   = { 8.h   * task.attempt }
}

withLabel:process_high {
    cpus   = { 12    * task.attempt }
    memory = { 72.GB * task.attempt }
    time   = { 16.h  * task.attempt }
}

withLabel:process_high_memory {
    memory = { 200.GB * task.attempt }
}
```

**Resource Tier Summary:**

| Label | CPUs | Memory | Time | Use Case |
|-------|------|--------|------|----------|
| `process_single` | 1 | 6 GB | 4h | Light tasks (formatting) |
| `process_low` | 2 | 12 GB | 4h | Basic analysis (QC) |
| `process_medium` | 6 | 36 GB | 8h | Standard (alignment) |
| `process_high` | 12 | 72 GB | 16h | Heavy (variant calling) |
| `process_high_memory` | - | 200 GB | - | Graph assembly |

### 2.2 Automatic Retry Scaling

Resources multiply on failure retry:
```groovy
memory = { 12.GB * task.attempt }  // 1st: 12GB, 2nd: 24GB, 3rd: 36GB
```

### 2.3 Maximum Resource Limits

`check_max()` function prevents exceeding system limits:

```groovy
def check_max(obj, type) {
    if (type == 'memory') {
        if (obj.compareTo(params.max_memory as MemoryUnit) == 1)
            return params.max_memory
        else
            return obj
    }
    // Similar for 'time' and 'cpus'
}

params {
    max_memory = '128.GB'
    max_cpus   = 16
    max_time   = '240.h'
}
```

### 2.4 Progressive Tuning for Cost Estimation

**Location:** `backend/lib/galaxy/ai/progressive_tuning.py`

This is a sophisticated system that:
1. Runs workflow on 5-15% of data first (pilot)
2. Collects actual metrics
3. Extrapolates to full dataset

```python
@dataclass
class PilotMetrics:
    runtime_seconds: float
    peak_memory_gb: float
    cpu_utilization: float = 0.0
    output_file_count: int = 0
    output_size_mb: float = 0.0
    quality_metrics: Dict[str, float] = field(default_factory=dict)
    step_metrics: Dict[str, Dict[str, float]] = field(default_factory=dict)

@dataclass
class FullRunEstimate:
    estimated_runtime_seconds: float
    estimated_runtime_display: str
    estimated_memory_gb: float
    estimated_cost_usd: Optional[float] = None
    confidence: float = 0.8
    scaling_factors: Dict[str, float] = field(default_factory=dict)
```

**Scaling Formulas:**
```python
scaling_factor = full_sample_count / pilot_samples

# Runtime scales sublinearly (0.85 power law)
runtime_scaling = scaling_factor ** 0.85
estimated_runtime = pilot_runtime * runtime_scaling

# Memory scales modestly (30% of linear)
memory_scaling = 1 + (scaling_factor - 1) * 0.3
estimated_memory = pilot_memory * memory_scaling

# Cost calculation
hours = estimated_runtime / 3600
estimated_cost = hours * cost_per_hour_usd  # Default: $0.50/hour
```

### 2.5 Execution Traces

Nextflow generates comprehensive execution reports:

```groovy
timeline { enabled = true; file = "execution_timeline.html" }
report { enabled = true; file = "execution_report.html" }
trace { enabled = true; file = "execution_trace.txt" }
dag { enabled = true; file = "pipeline_dag.html" }
```

---

## 3. Current Biomate Database Schema Assessment

### 3.1 Existing Tables (Sufficient for Tracking)

| Table | Purpose | Key Fields |
|-------|---------|------------|
| `job` | Job execution records | `tool_id`, `state`, `exit_code`, `destination_params` |
| `job_metric_numeric` | Numeric metrics | `job_id`, `plugin`, `metric_name`, `metric_value` |
| `job_metric_text` | Text metrics | `job_id`, `plugin`, `metric_name`, `metric_value` |
| `workflow_invocation` | Workflow execution | `workflow_id`, `state`, `scheduler` |
| `workflow_invocation_step` | Step tracking | `job_id`, `state`, `action` |
| `workflow_request_input_parameters` | Input params | `name`, `value`, `type` (includes `RESOURCE_PARAMETERS`) |

### 3.2 Key Finding: Resource Parameters Support Exists

The `WorkflowRequestInputParameter` table already supports resource specifications:

```python
# backend/lib/galaxy/model/__init__.py
class types(str, Enum):
    REPLACEMENT_PARAMETERS = "replacements"
    STEP_PARAMETERS = "step"
    META_PARAMETERS = "meta"
    RESOURCE_PARAMETERS = "resource"  # <-- Already exists!

def resource_parameters(self):
    """Get resource parameters for this invocation"""
    resource_type = WorkflowRequestInputParameter.types.RESOURCE_PARAMETERS
    _resource_parameters = {}
    for input_parameter in self.input_parameters:
        if input_parameter.type == resource_type:
            _resource_parameters[input_parameter.name] = input_parameter.value
    return _resource_parameters
```

### 3.3 Missing Fields

| Missing Data | Current Workaround | Impact |
|--------------|-------------------|--------|
| Tool resource requirements | Docs in `<help>` text | Can't validate before run |
| Estimated cost per tool | None | Can't show user cost |
| Actual job cost | None | Can't track revenue/cost |
| Max input size | None | Jobs may fail |
| Output size estimate | None | May exceed disk quota |

---

## 4. Gap Analysis Summary

| Capability | Galaxy | Nextflow | Biomate | Gap |
|------------|--------|----------|---------|-----|
| **Structured resource specs** | No | Yes (labels) | No | Critical |
| **Memory requirements** | Docs only | Config | No | Critical |
| **CPU requirements** | Docs only | Config | No | Critical |
| **GPU requirements** | Docs only | Partial | No | Important |
| **Max input size** | No | No | No | Important |
| **Output size estimate** | No | No | No | Moderate |
| **Cost estimation** | No | Yes (progressive tuning) | Partial | Critical |
| **Per-job cost tracking** | No | Yes (traces) | No | Critical |
| **Max resource limits** | Concurrency only | `check_max()` | Concurrency only | Important |
| **Retry scaling** | No | Yes (`* task.attempt`) | No | Nice-to-have |

---

## 5. Proposed Implementation Plan

### Phase 1: Structured Tool Metadata (Week 1-2)

**Goal:** Machine-readable resource specifications for all tools

#### 5.1.1 Tool XML Schema Extension

```xml
<tool id="alphafold3" name="AlphaFold 3" version="3.0">
    <description>Biomolecular complex structure prediction</description>

    <!-- NEW: Structured resource specifications -->
    <resources>
        <memory min="40" max="100" recommended="80" unit="GB"/>
        <cpu min="4" max="16" recommended="8"/>
        <gpu required="true" vram="80" unit="GB"/>
        <disk min="100" unit="GB"/>
        <time min="30" max="120" unit="minutes"/>
        <cost min="0.50" max="2.00" currency="USD" per="run"/>
        <capacity max_input_size="10" unit="MB" description="Total sequence length"/>
    </resources>

    <requirements>
        <container type="docker">ghcr.io/biomate/alphafold3:3.0</container>
    </requirements>
</tool>
```

#### 5.1.2 Database Schema (New Table)

```sql
CREATE TABLE tool_resource_spec (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id VARCHAR(255) NOT NULL,
    tool_version VARCHAR(64),

    -- Memory (in GB)
    min_memory_gb DECIMAL(10,2),
    max_memory_gb DECIMAL(10,2),
    recommended_memory_gb DECIMAL(10,2),

    -- CPU
    min_cpu INTEGER,
    max_cpu INTEGER,
    recommended_cpu INTEGER,

    -- GPU
    gpu_required BOOLEAN DEFAULT FALSE,
    gpu_vram_gb DECIMAL(10,2),

    -- Disk
    min_disk_gb DECIMAL(10,2),

    -- Time (in minutes)
    min_runtime_minutes INTEGER,
    max_runtime_minutes INTEGER,

    -- Cost
    min_cost_usd DECIMAL(10,4),
    max_cost_usd DECIMAL(10,4),
    cost_per_hour_usd DECIMAL(10,4),

    -- Capacity limits
    max_input_size_mb DECIMAL(10,2),
    max_input_records INTEGER,
    output_size_factor DECIMAL(5,2),  -- output = input * factor

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tool_id, tool_version)
);

CREATE INDEX idx_tool_resource_spec_tool_id ON tool_resource_spec(tool_id);
```

#### 5.1.3 Tool XML Parser Update

```python
# backend/lib/galaxy/tools/__init__.py
def parse_resources(self, tool_source):
    """Parse <resources> element from tool XML"""
    resources = {}
    resources_elem = tool_source.xml_tree.find('resources')
    if resources_elem is not None:
        # Memory
        memory = resources_elem.find('memory')
        if memory is not None:
            resources['memory'] = {
                'min': float(memory.get('min', 0)),
                'max': float(memory.get('max', 0)),
                'recommended': float(memory.get('recommended', 0)),
                'unit': memory.get('unit', 'GB')
            }
        # ... similar for cpu, gpu, disk, time, cost, capacity
    return resources
```

### Phase 2: Cost Tracking (Week 2-3)

**Goal:** Track actual costs per job and workflow

#### 5.2.1 Job Table Extension

```sql
ALTER TABLE job ADD COLUMN estimated_cost_usd DECIMAL(10,4);
ALTER TABLE job ADD COLUMN actual_cost_usd DECIMAL(10,4);
ALTER TABLE job ADD COLUMN cost_calculation_method VARCHAR(50);
```

#### 5.2.2 Workflow Invocation Extension

```sql
ALTER TABLE workflow_invocation ADD COLUMN estimated_total_cost_usd DECIMAL(10,4);
ALTER TABLE workflow_invocation ADD COLUMN actual_total_cost_usd DECIMAL(10,4);
ALTER TABLE workflow_invocation ADD COLUMN user_cost_approved BOOLEAN DEFAULT FALSE;
ALTER TABLE workflow_invocation ADD COLUMN cost_approved_at TIMESTAMP;
```

#### 5.2.3 Cost Calculation Service

```python
# backend/lib/galaxy/jobs/cost_estimator.py

class CostEstimator:
    DEFAULT_COST_PER_CPU_HOUR = 0.05  # $0.05 per CPU-hour
    DEFAULT_COST_PER_GB_HOUR = 0.01   # $0.01 per GB-hour
    DEFAULT_COST_PER_GPU_HOUR = 0.50  # $0.50 per GPU-hour

    def estimate_job_cost(self, tool_id: str, input_size_mb: float) -> CostEstimate:
        """Estimate cost before job execution"""
        spec = self.get_tool_resource_spec(tool_id)

        # Calculate resource-hours
        cpu_hours = spec.recommended_cpu * (spec.max_runtime_minutes / 60)
        memory_gb_hours = spec.recommended_memory_gb * (spec.max_runtime_minutes / 60)
        gpu_hours = (spec.max_runtime_minutes / 60) if spec.gpu_required else 0

        # Calculate cost
        cost = (
            cpu_hours * self.DEFAULT_COST_PER_CPU_HOUR +
            memory_gb_hours * self.DEFAULT_COST_PER_GB_HOUR +
            gpu_hours * self.DEFAULT_COST_PER_GPU_HOUR
        )

        return CostEstimate(
            min_cost=spec.min_cost_usd or cost * 0.8,
            max_cost=spec.max_cost_usd or cost * 1.5,
            estimated_cost=cost,
            confidence=0.7,
            breakdown={
                'cpu': cpu_hours * self.DEFAULT_COST_PER_CPU_HOUR,
                'memory': memory_gb_hours * self.DEFAULT_COST_PER_GB_HOUR,
                'gpu': gpu_hours * self.DEFAULT_COST_PER_GPU_HOUR
            }
        )

    def calculate_actual_cost(self, job: Job) -> float:
        """Calculate actual cost from job metrics"""
        metrics = self.get_job_metrics(job.id)

        runtime_hours = metrics.get('runtime_seconds', 0) / 3600
        cpu_used = metrics.get('galaxy_slots', 1)
        memory_gb = metrics.get('galaxy_memory_mb', 0) / 1024

        actual_cost = (
            runtime_hours * cpu_used * self.DEFAULT_COST_PER_CPU_HOUR +
            runtime_hours * memory_gb * self.DEFAULT_COST_PER_GB_HOUR
        )

        return actual_cost
```

### Phase 3: User-Facing Cost Confirmation (Week 3-4)

**Goal:** Show users cost estimates and get approval before running

#### 5.3.1 API Endpoint

```python
# backend/lib/galaxy/webapps/galaxy/api/workflows.py

@router.post("/api/workflows/{workflow_id}/estimate_cost")
async def estimate_workflow_cost(
    workflow_id: str,
    inputs: WorkflowInputs,
    trans: ProvidesUserContext = DependsOnTrans
) -> WorkflowCostEstimate:
    """Estimate cost before running workflow"""
    workflow = self._get_stored_workflow(trans, workflow_id)

    total_estimate = CostEstimate()
    step_estimates = []

    for step in workflow.steps:
        if step.type == 'tool':
            input_size = calculate_input_size(inputs, step)
            estimate = cost_estimator.estimate_job_cost(step.tool_id, input_size)
            step_estimates.append({
                'step_id': step.id,
                'tool_id': step.tool_id,
                'estimate': estimate
            })
            total_estimate += estimate

    return WorkflowCostEstimate(
        workflow_id=workflow_id,
        total_estimate=total_estimate,
        step_estimates=step_estimates,
        warnings=self._get_resource_warnings(workflow, inputs)
    )
```

#### 5.3.2 Frontend Component

```typescript
// frontend/client/src/components/workflow-cost-estimate.tsx

interface WorkflowCostEstimateProps {
  workflowId: string;
  inputs: WorkflowInputs;
  onApprove: () => void;
  onCancel: () => void;
}

export function WorkflowCostEstimate({ workflowId, inputs, onApprove, onCancel }: WorkflowCostEstimateProps) {
  const { data: estimate } = useQuery(['workflow-cost', workflowId], () =>
    api.estimateWorkflowCost(workflowId, inputs)
  );

  return (
    <Dialog>
      <DialogTitle>Estimated Resource Usage</DialogTitle>
      <DialogContent>
        <Table>
          <TableRow>
            <TableCell>Estimated Runtime</TableCell>
            <TableCell>{estimate.estimatedRuntime}</TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Peak Memory</TableCell>
            <TableCell>{estimate.peakMemoryGb} GB</TableCell>
          </TableRow>
          <TableRow>
            <TableCell>Estimated Cost</TableCell>
            <TableCell>${estimate.minCost.toFixed(2)} - ${estimate.maxCost.toFixed(2)}</TableCell>
          </TableRow>
        </Table>

        {estimate.warnings.map(warning => (
          <Alert severity="warning">{warning}</Alert>
        ))}
      </DialogContent>
      <DialogActions>
        <Button onClick={onCancel}>Cancel</Button>
        <Button onClick={() => runPilot(0.15)}>Run Pilot First (15%)</Button>
        <Button onClick={onApprove} variant="contained">Confirm & Run</Button>
      </DialogActions>
    </Dialog>
  );
}
```

### Phase 4: Progressive Tuning Integration (Week 4-5)

**Goal:** Leverage existing `progressive_tuning.py` for accurate estimates

```python
# Expose progressive tuning to workflow API
@router.post("/api/workflows/{workflow_id}/run_pilot")
async def run_workflow_pilot(
    workflow_id: str,
    inputs: WorkflowInputs,
    pilot_fraction: float = 0.15,
    trans: ProvidesUserContext = DependsOnTrans
) -> PilotRunResult:
    """Run workflow on subset of data to estimate full cost"""

    # Sample inputs
    sampled_inputs = progressive_tuner.sample_inputs(inputs, pilot_fraction)

    # Run pilot
    invocation = await self._run_workflow(workflow_id, sampled_inputs, trans)

    # Wait for completion and collect metrics
    pilot_metrics = await progressive_tuner.collect_pilot_metrics(invocation)

    # Extrapolate to full run
    full_estimate = progressive_tuner.estimate_full_run(
        pilot_metrics=pilot_metrics,
        pilot_samples=len(sampled_inputs),
        full_sample_count=len(inputs)
    )

    return PilotRunResult(
        pilot_invocation_id=invocation.id,
        pilot_metrics=pilot_metrics,
        full_run_estimate=full_estimate
    )
```

---

## 6. Priority Matrix

| Feature | Business Value | Technical Effort | Priority |
|---------|---------------|------------------|----------|
| Tool resource specs in XML | High | Medium | P0 |
| tool_resource_spec DB table | High | Low | P0 |
| Cost estimation API | High | Medium | P0 |
| Per-job cost tracking | High | Low | P1 |
| Frontend cost confirmation | High | Medium | P1 |
| Progressive tuning exposure | Medium | Low | P2 |
| Output size estimation | Medium | Medium | P2 |
| Retry scaling | Low | Medium | P3 |

---

## 7. Team Discussion Points

1. **Pricing Model:** Should we offer usage-based pricing alongside subscriptions?
   - Current: Flat $20/mo
   - Proposed: $X base + usage overage?

2. **Cost Per Resource:** What are our actual infrastructure costs?
   - Need AWS/GCP cost data to set realistic prices
   - Current progressive_tuning uses $0.50/hour default

3. **GPU Tools:** Special pricing for GPU-intensive tools?
   - AlphaFold3, Boltz2, etc. require 80GB+ VRAM
   - Significant cost difference from CPU-only tools

4. **Pilot Runs:** Should pilot runs be free/discounted?
   - Encourages users to estimate before committing
   - Could be 15-20% of full cost

5. **Tool Capacity Limits:** How do we handle over-capacity requests?
   - Reject? Queue? Warn and proceed?
   - Example: User submits 1GB FASTA to tool with 100MB max

6. **Data Retention:** How long to keep job metrics?
   - Needed for billing disputes
   - Storage cost vs compliance needs

---

## 8. Appendix: Key File Locations

### Configuration
- `backend/config/job_conf.yml` - Job execution configuration
- `backend/config/galaxy.yml` - Galaxy server configuration
- `backend/config/auth_payment_config.yml.example` - Billing configuration

### Models
- `backend/lib/galaxy/model/__init__.py` - Database models (Job, JobMetric*, Workflow*)

### Job Metrics
- `backend/lib/galaxy/job_metrics/instrumenters/core.py` - Core metrics (slots, memory, runtime)
- `backend/lib/galaxy/job_metrics/instrumenters/cgroup.py` - CGroup metrics (peak memory, CPU time)

### Progressive Tuning
- `backend/lib/galaxy/ai/progressive_tuning.py` - Pilot-based cost estimation

### Nextflow Resources
- `backend/nf-core-workflows/rnaseq/conf/base.config` - Resource tier definitions
- `backend/nf-core-workflows/differentialabundance/nextflow.config` - check_max() implementation

### Tool Definitions
- `backend/tools/biomate_ai_tools/*.xml` - AI tool definitions
- `backend/biomni_workflows/galaxy/tools/biomni/**/*.xml` - Biomni tool definitions

---

## 9. Next Steps

1. [ ] Review this document with team
2. [ ] Get AWS cost data for pricing decisions
3. [ ] Prioritize features for MVP
4. [ ] Create Alembic migration for new tables
5. [ ] Update tool XML schema documentation
6. [ ] Implement cost estimation API
7. [ ] Add frontend cost confirmation flow
