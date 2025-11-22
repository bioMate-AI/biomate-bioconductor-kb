# Galaxy-Nextflow Workflow Integration Architecture

**Date:** 2025-11-19
**Status:** Implementation Plan
**Purpose:** Enable BioMate to use both Galaxy and Nextflow workflows with unified UI and bidirectional conversion

---

## Executive Summary

This architecture enables BioMate to:
1. **Present workflows in a unified, high-level UI** - abstract implementation details
2. **Execute Galaxy workflows via Nextflow on AWS Batch** - leverage cloud scalability
3. **Trace Nextflow workflows via Galaxy format** - unified monitoring and provenance
4. **Convert bidirectionally** - Galaxy ↔ Nextflow transformation

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    1. UI PRESENTATION LAYER                      │
│                                                                  │
│  High-Level Workflow Steps (Domain-Agnostic)                   │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                │
│  │ QC       │ →  │ Align    │ →  │ Quantify │                │
│  │ (expand) │    │ (expand) │    │ (expand) │                │
│  └──────────┘    └──────────┘    └──────────┘                │
│                                                                  │
│  On Click: Show detailed steps, parameters, tool info          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              2. WORKFLOW ABSTRACTION LAYER                       │
│                                                                  │
│  BioMate Unified Workflow Format (BUWF)                        │
│  {                                                               │
│    "workflow_id": "uuid",                                       │
│    "name": "RNA-seq Analysis",                                  │
│    "high_level_steps": [                                        │
│      {                                                           │
│        "step_id": "qc",                                         │
│        "name": "Quality Control",                               │
│        "description": "Assess read quality and trim adapters", │
│        "detailed_steps": [                                      │
│          {"tool": "fastqc", "params": {...}},                  │
│          {"tool": "trimmomatic", "params": {...}}              │
│        ],                                                        │
│        "inputs": [...],                                         │
│        "outputs": [...]                                         │
│      },                                                          │
│      ...                                                         │
│    ],                                                            │
│    "source_format": "galaxy|nextflow",                          │
│    "execution_engine": "galaxy|nextflow"                        │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
                            ↓
            ┌───────────────┴───────────────┐
            │                               │
            ↓                               ↓
┌──────────────────────────┐  ┌──────────────────────────┐
│ 3A. GALAXY BACKEND       │  │ 3B. NEXTFLOW BACKEND     │
│     (Tracing)            │  │     (Execution)          │
│                          │  │                          │
│  Galaxy .ga format       │  │  Nextflow .nf format     │
│  - Workflow tracking     │  │  - Process definition    │
│  - Provenance            │  │  - Channel data flow     │
│  - Tool metadata         │  │  - Container specs       │
│  - Parameter recording   │  │  - AWS Batch integration │
└──────────────────────────┘  └──────────────────────────┘
            │                               │
            │                               │
            ↓                               ↓
┌──────────────────────────┐  ┌──────────────────────────┐
│ 4A. GALAXY EXECUTOR      │  │ 4B. NEXTFLOW EXECUTOR    │
│     (Current)            │  │     (Future/AWS)         │
│                          │  │                          │
│  - Local execution       │  │  - AWS Batch             │
│  - Tool execution        │  │  - S3 storage            │
│  - Job management        │  │  - Auto-scaling          │
└──────────────────────────┘  └──────────────────────────┘
```

---

## Core Components

### 1. Workflow Abstraction Layer

**Purpose**: Unified workflow representation that abstracts both Galaxy and Nextflow specifics.

#### BioMate Unified Workflow Format (BUWF)

```python
class UnifiedWorkflow:
    """
    Domain-agnostic workflow representation.

    Supports both Galaxy and Nextflow source formats.
    """
    workflow_id: str
    name: str
    description: str

    # High-level steps for UI presentation
    high_level_steps: List[HighLevelStep]

    # Source and target formats
    source_format: Literal["galaxy", "nextflow", "buwf"]
    execution_engine: Literal["galaxy", "nextflow"]

    # Metadata
    creator: str
    license: str
    tags: List[str]
    created_at: datetime
    modified_at: datetime


class HighLevelStep:
    """
    High-level workflow step (user-facing abstraction).

    Example: "Quality Control" encompasses FastQC + Trimmomatic
    """
    step_id: str
    name: str
    description: str

    # Detailed implementation (expandable in UI)
    detailed_steps: List[DetailedStep]

    # Data flow
    inputs: List[DataInput]
    outputs: List[DataOutput]

    # Parameters (with smart defaults)
    parameters: Dict[str, Parameter]

    # Grouping metadata
    category: str  # "qc", "alignment", "quantification", etc.
    icon: str
    color: str


class DetailedStep:
    """
    Individual tool execution step.

    Maps to:
    - Galaxy: workflow step (tool invocation)
    - Nextflow: process invocation
    """
    tool_id: str
    tool_name: str
    tool_version: str

    # Tool-specific parameters
    parameters: Dict[str, Any]

    # Input/output connections
    inputs: List[str]  # References to previous step outputs
    outputs: List[str]  # Output names

    # Execution metadata
    container: str
    cpu: int
    memory: str
    runtime_estimate: int
```

---

### 2. Conversion System

#### 2.1 Galaxy → BUWF Converter

**Purpose**: Parse Galaxy .ga workflows into unified format.

```python
class GalaxyToUnifiedConverter:
    """
    Convert Galaxy .ga workflow to BioMate Unified Workflow Format.

    Strategy:
    1. Parse .ga JSON
    2. Group sequential tool steps into high-level steps
    3. Extract parameters and data flow
    4. Map tool IDs to BioMate tool database
    """

    def convert(self, galaxy_workflow: Dict) -> UnifiedWorkflow:
        """
        Main conversion entry point.

        Steps:
        1. Extract workflow metadata
        2. Parse workflow steps
        3. Identify high-level step boundaries
        4. Build unified workflow structure
        """

        # 1. Extract metadata
        metadata = self._extract_metadata(galaxy_workflow)

        # 2. Parse all steps
        galaxy_steps = galaxy_workflow.get("steps", {})
        parsed_steps = self._parse_galaxy_steps(galaxy_steps)

        # 3. Group into high-level steps
        high_level_steps = self._group_into_high_level_steps(parsed_steps)

        # 4. Build unified workflow
        return UnifiedWorkflow(
            workflow_id=str(uuid.uuid4()),
            name=metadata["name"],
            description=metadata["annotation"],
            high_level_steps=high_level_steps,
            source_format="galaxy",
            execution_engine="galaxy",  # Default, can be changed
            **metadata
        )

    def _group_into_high_level_steps(
        self,
        steps: List[Dict]
    ) -> List[HighLevelStep]:
        """
        Group sequential Galaxy tool steps into logical high-level steps.

        Grouping heuristics:
        1. **Function-based**: Tools with similar function (QC, alignment, etc.)
        2. **Annotation-based**: Steps with similar annotations
        3. **Data flow**: Steps that process the same dataset sequentially
        4. **Tool patterns**: Known tool combinations (e.g., FastQC → MultiQC)

        Example groupings:
        - FastQC + MultiQC → "Quality Control"
        - BWA-MEM + SAMtools sort + SAMtools index → "Read Alignment"
        - featureCounts + DESeq2 → "Differential Expression"
        """

        # Use pattern matching and ML to identify logical groupings
        grouped = []
        current_group = None

        for step in steps:
            # Determine if this step should start a new group
            if self._should_start_new_group(step, current_group):
                if current_group:
                    grouped.append(self._finalize_group(current_group))
                current_group = self._create_new_group(step)
            else:
                current_group["steps"].append(step)

        if current_group:
            grouped.append(self._finalize_group(current_group))

        return grouped
```

#### 2.2 Nextflow → BUWF Converter

**Purpose**: Parse Nextflow .nf workflows into unified format.

```python
class NextflowToUnifiedConverter:
    """
    Convert Nextflow .nf workflow to BioMate Unified Workflow Format.

    Strategy:
    1. Parse Nextflow DSL (Groovy)
    2. Extract workflow, processes, and channels
    3. Map processes to tools
    4. Build unified workflow structure

    Challenges:
    - Nextflow is imperative (processes) vs Galaxy declarative (JSON)
    - Need to parse Groovy DSL
    - Channel data flow is implicit
    """

    def convert(self, nextflow_file: Path) -> UnifiedWorkflow:
        """
        Main conversion entry point.

        Steps:
        1. Parse Nextflow DSL (use groovy parser or regex)
        2. Extract workflow structure
        3. Identify processes and data flow
        4. Map to unified format
        """

        # 1. Parse Nextflow file
        nf_structure = self._parse_nextflow_file(nextflow_file)

        # 2. Extract metadata
        metadata = self._extract_nextflow_metadata(nf_structure)

        # 3. Parse workflow and processes
        workflow_def = nf_structure.get("workflow", {})
        processes = nf_structure.get("processes", {})

        # 4. Build high-level steps from processes
        high_level_steps = self._build_high_level_steps_from_processes(
            workflow_def,
            processes
        )

        # 5. Build unified workflow
        return UnifiedWorkflow(
            workflow_id=str(uuid.uuid4()),
            name=metadata["name"],
            description=metadata["description"],
            high_level_steps=high_level_steps,
            source_format="nextflow",
            execution_engine="nextflow",
            **metadata
        )

    def _parse_nextflow_file(self, nf_file: Path) -> Dict:
        """
        Parse Nextflow DSL file.

        Options:
        1. **Regex-based parsing** (simple, fragile)
        2. **Groovy AST parsing** (complex, accurate)
        3. **Nextflow schema parsing** (if available)

        For now, use regex + heuristics for common patterns.
        """

        content = nf_file.read_text()

        # Extract workflow definition
        workflow_match = re.search(
            r'workflow\s+(\w+)\s*\{(.*?)\}',
            content,
            re.DOTALL
        )

        # Extract processes
        process_matches = re.findall(
            r'process\s+(\w+)\s*\{(.*?)\}',
            content,
            re.DOTALL
        )

        # Extract includes (subworkflows/modules)
        include_matches = re.findall(
            r'include\s*\{([^}]+)\}\s*from\s*[\'"]([^"\']+)[\'"]',
            content
        )

        return {
            "workflow": self._parse_workflow_body(workflow_match.group(2) if workflow_match else ""),
            "processes": self._parse_processes(process_matches),
            "includes": self._parse_includes(include_matches)
        }
```

#### 2.3 BUWF → Galaxy Converter

**Purpose**: Generate Galaxy .ga JSON from unified format.

```python
class UnifiedToGalaxyConverter:
    """
    Convert BioMate Unified Workflow to Galaxy .ga format.

    Strategy:
    1. Flatten high-level steps into individual tool steps
    2. Generate Galaxy step IDs and connections
    3. Map tool IDs to Galaxy ToolShed format
    4. Generate .ga JSON
    """

    def convert(self, unified_workflow: UnifiedWorkflow) -> Dict:
        """
        Main conversion entry point.

        Returns Galaxy .ga JSON.
        """

        galaxy_workflow = {
            "a_galaxy_workflow": "true",
            "format-version": "0.1",
            "name": unified_workflow.name,
            "annotation": unified_workflow.description,
            "tags": unified_workflow.tags,
            "creator": self._format_creator(unified_workflow.creator),
            "license": unified_workflow.license,
            "steps": {}
        }

        # Generate Galaxy steps from high-level steps
        step_id = 0
        for high_level_step in unified_workflow.high_level_steps:
            # Flatten detailed steps
            for detailed_step in high_level_step.detailed_steps:
                galaxy_step = self._convert_to_galaxy_step(
                    detailed_step,
                    step_id
                )
                galaxy_workflow["steps"][str(step_id)] = galaxy_step
                step_id += 1

        return galaxy_workflow

    def _convert_to_galaxy_step(
        self,
        detailed_step: DetailedStep,
        step_id: int
    ) -> Dict:
        """
        Convert unified detailed step to Galaxy step format.
        """

        # Map tool ID to Galaxy ToolShed format
        tool_id = self._map_to_galaxy_tool_id(detailed_step.tool_id)

        return {
            "id": step_id,
            "type": "tool",
            "tool_id": tool_id,
            "tool_version": detailed_step.tool_version,
            "name": detailed_step.tool_name,
            "annotation": detailed_step.description,
            "tool_state": self._encode_tool_state(detailed_step.parameters),
            "input_connections": self._build_input_connections(detailed_step),
            "workflow_outputs": self._mark_workflow_outputs(detailed_step),
            "position": {
                "left": step_id * 220 + 10,
                "top": 10
            }
        }
```

#### 2.4 BUWF → Nextflow Converter

**Purpose**: Generate Nextflow .nf script from unified format.

```python
class UnifiedToNextflowConverter:
    """
    Convert BioMate Unified Workflow to Nextflow .nf format.

    Strategy:
    1. Generate Nextflow workflow structure
    2. Create process definitions for each tool
    3. Define channels and data flow
    4. Generate .nf script

    This is more complex than Galaxy generation because:
    - Nextflow is imperative (not declarative JSON)
    - Need to generate valid Groovy code
    - Channel management is explicit
    """

    def convert(
        self,
        unified_workflow: UnifiedWorkflow
    ) -> Dict[str, str]:
        """
        Main conversion entry point.

        Returns dict with:
        - "main.nf": Main workflow file
        - "nextflow.config": Configuration file
        - "modules/{tool}.nf": Individual tool modules
        """

        modules = {}
        channel_defs = []
        workflow_body = []

        # Generate modules for each tool
        for high_level_step in unified_workflow.high_level_steps:
            for detailed_step in high_level_step.detailed_steps:
                # Generate Nextflow process
                module_code = self._generate_nextflow_process(detailed_step)
                modules[f"modules/{detailed_step.tool_id}.nf"] = module_code

                # Add to workflow
                workflow_body.append(
                    self._generate_process_invocation(detailed_step)
                )

        # Generate main workflow
        main_nf = self._generate_main_workflow(
            unified_workflow,
            workflow_body
        )

        # Generate config
        config = self._generate_nextflow_config(unified_workflow)

        return {
            "main.nf": main_nf,
            "nextflow.config": config,
            **modules
        }

    def _generate_nextflow_process(
        self,
        detailed_step: DetailedStep
    ) -> str:
        """
        Generate Nextflow process definition.

        Template:
        ```nextflow
        process TOOL_NAME {
            tag "$meta.id"
            label 'process_medium'

            container "${ container_image }"

            input:
            tuple val(meta), path(input_files)

            output:
            tuple val(meta), path("*.output"), emit: output
            path "versions.yml", emit: versions

            script:
            \"\"\"
            tool_command \\
                --input $input_files \\
                --param1 ${params.param1} \\
                --output output.txt

            cat <<-END_VERSIONS > versions.yml
            "${task.process}":
                tool: \$(tool --version)
            END_VERSIONS
            \"\"\"
        }
        ```
        """

        template = f"""
process {detailed_step.tool_name.upper().replace('-', '_')} {{
    tag "$meta.id"
    label 'process_medium'

    container "{detailed_step.container}"

    input:
    {self._generate_input_spec(detailed_step)}

    output:
    {self._generate_output_spec(detailed_step)}

    script:
    \"\"\"
    {self._generate_tool_command(detailed_step)}

    cat <<-END_VERSIONS > versions.yml
    "${{task.process}}":
        {detailed_step.tool_name}: \\$({detailed_step.tool_name} --version)
    END_VERSIONS
    \"\"\"
}}
"""
        return template
```

---

### 3. High-Level Step Grouping Logic

**Challenge**: Both Galaxy and Nextflow have fine-grained tool steps. We need to group them into meaningful high-level steps for UI presentation.

#### Grouping Strategies

1. **Function-Based Grouping** - Group by biological function
2. **Annotation-Based** - Use workflow annotations/comments
3. **Pattern-Based** - Detect known tool patterns
4. **ML-Based** - Learn from existing workflow collections (IWC, nf-core)

#### Implementation

```python
class WorkflowStepGrouper:
    """
    Group fine-grained workflow steps into high-level logical steps.

    Uses multiple strategies:
    1. Tool function patterns (QC tools → QC step)
    2. IWC/nf-core subworkflow structure
    3. Annotation hints
    4. Data flow analysis
    """

    # Known tool grouping patterns (from IWC analysis)
    GROUPING_PATTERNS = {
        "Quality Control": {
            "tools": ["fastqc", "multiqc", "trimmomatic", "cutadapt", "fastp"],
            "keywords": ["qc", "quality", "trim", "filter"],
            "icon": "🔍",
            "color": "#3498db"
        },
        "Read Alignment": {
            "tools": ["bwa", "bowtie2", "star", "hisat2", "minimap2",
                      "samtools_sort", "samtools_index"],
            "keywords": ["align", "map", "sort", "index"],
            "icon": "🧬",
            "color": "#2ecc71"
        },
        "Quantification": {
            "tools": ["featurecounts", "htseq", "salmon", "kallisto",
                      "rsem", "stringtie"],
            "keywords": ["count", "quantif", "expression"],
            "icon": "📊",
            "color": "#9b59b6"
        },
        "Differential Expression": {
            "tools": ["deseq2", "edger", "limma"],
            "keywords": ["differential", "de_analysis", "dge"],
            "icon": "📈",
            "color": "#e74c3c"
        },
        "Variant Calling": {
            "tools": ["gatk", "bcftools", "freebayes", "lofreq"],
            "keywords": ["variant", "snp", "indel", "vcf"],
            "icon": "🔬",
            "color": "#f39c12"
        },
        "Peak Calling": {
            "tools": ["macs2", "homer"],
            "keywords": ["peak", "chip", "atac"],
            "icon": "⛰️",
            "color": "#1abc9c"
        }
    }

    def group_steps(
        self,
        steps: List[DetailedStep]
    ) -> List[HighLevelStep]:
        """
        Group detailed steps into high-level steps.

        Strategy:
        1. Try pattern matching first (fast)
        2. Fall back to annotation analysis
        3. Use data flow analysis as last resort
        """

        # 1. Pattern-based grouping
        grouped = self._group_by_patterns(steps)

        # 2. Refine with annotations
        grouped = self._refine_with_annotations(grouped, steps)

        # 3. Handle ungrouped steps
        grouped = self._handle_ungrouped_steps(grouped, steps)

        return grouped

    def _group_by_patterns(
        self,
        steps: List[DetailedStep]
    ) -> List[HighLevelStep]:
        """
        Group steps using known tool patterns.
        """
        groups = []
        used_step_ids = set()

        # Try to match each pattern
        for pattern_name, pattern_def in self.GROUPING_PATTERNS.items():
            matching_steps = []

            for step in steps:
                if step.step_id in used_step_ids:
                    continue

                # Check if tool matches pattern
                if self._matches_pattern(step, pattern_def):
                    matching_steps.append(step)
                    used_step_ids.add(step.step_id)

            if matching_steps:
                groups.append(HighLevelStep(
                    step_id=f"hl_{len(groups)}",
                    name=pattern_name,
                    description=self._generate_description(
                        pattern_name,
                        matching_steps
                    ),
                    detailed_steps=matching_steps,
                    category=pattern_name.lower().replace(" ", "_"),
                    icon=pattern_def["icon"],
                    color=pattern_def["color"]
                ))

        return groups
```

---

### 4. UI Integration

#### Frontend Components

```typescript
// components/WorkflowVisualization.tsx

interface HighLevelStepProps {
  step: HighLevelStep;
  expanded: boolean;
  onToggle: () => void;
}

const HighLevelStepCard: React.FC<HighLevelStepProps> = ({
  step,
  expanded,
  onToggle
}) => {
  return (
    <Card className="workflow-step">
      <CardHeader onClick={onToggle}>
        <div className="flex items-center gap-3">
          <span className="text-2xl">{step.icon}</span>
          <div>
            <h3 className="text-lg font-semibold">{step.name}</h3>
            <p className="text-sm text-gray-600">{step.description}</p>
          </div>
          <Badge>{step.detailed_steps.length} tools</Badge>
        </div>
      </CardHeader>

      {expanded && (
        <CardContent>
          <div className="space-y-4">
            {step.detailed_steps.map((detailStep, idx) => (
              <DetailedStepCard key={idx} step={detailStep} />
            ))}
          </div>

          <div className="mt-4 p-4 bg-gray-50 rounded">
            <h4 className="font-semibold mb-2">Parameters</h4>
            <ParameterEditor parameters={step.parameters} />
          </div>
        </CardContent>
      )}
    </Card>
  );
};


const WorkflowCanvas: React.FC<{workflow: UnifiedWorkflow}> = ({
  workflow
}) => {
  const [expandedSteps, setExpandedSteps] = useState<Set<string>>(new Set());

  return (
    <div className="workflow-canvas">
      {workflow.high_level_steps.map((step, idx) => (
        <div key={step.step_id} className="workflow-step-container">
          <HighLevelStepCard
            step={step}
            expanded={expandedSteps.has(step.step_id)}
            onToggle={() => toggleStep(step.step_id)}
          />

          {idx < workflow.high_level_steps.length - 1 && (
            <div className="workflow-arrow">↓</div>
          )}
        </div>
      ))}
    </div>
  );
};
```

---

### 5. Execution Architecture

#### Galaxy Execution (Current)

```python
class GalaxyExecutor:
    """
    Execute workflows using Galaxy backend.

    Current implementation - no changes needed.
    """

    def execute(self, unified_workflow: UnifiedWorkflow):
        # Convert to Galaxy format
        galaxy_workflow = UnifiedToGalaxyConverter().convert(unified_workflow)

        # Execute via Galaxy API
        return self.galaxy_api.run_workflow(galaxy_workflow)
```

#### Nextflow Execution (Future/AWS)

```python
class NextflowExecutor:
    """
    Execute workflows using Nextflow on AWS Batch.

    Based on NEXTFLOW_INTEGRATION.md architecture.
    """

    def execute(self, unified_workflow: UnifiedWorkflow):
        # Convert to Nextflow format
        nf_files = UnifiedToNextflowConverter().convert(unified_workflow)

        # Upload to execution environment
        work_dir = self._prepare_execution_environment(nf_files)

        # Launch Nextflow
        result = self._launch_nextflow(work_dir, unified_workflow)

        # Monitor execution
        return self._monitor_execution(result)

    def _launch_nextflow(self, work_dir: Path, workflow: UnifiedWorkflow):
        """
        Launch Nextflow with AWS Batch executor.

        Uses configuration from NEXTFLOW_INTEGRATION.md:
        - AWS Batch queue
        - S3 work directory
        - Container images
        """

        cmd = [
            "nextflow",
            "run",
            str(work_dir / "main.nf"),
            "-c", str(work_dir / "nextflow.config"),
            "-profile", "aws_batch",
            "-work-dir", f"s3://{self.s3_bucket}/work/{workflow.workflow_id}"
        ]

        process = subprocess.Popen(cmd, ...)
        return process
```

---

## Implementation Plan

### Phase 1: Core Abstraction Layer (Week 1)

**Goal**: Build unified workflow format and basic converters

- [ ] Define `UnifiedWorkflow`, `HighLevelStep`, `DetailedStep` classes
- [ ] Implement `GalaxyToUnifiedConverter`
- [ ] Implement `UnifiedToGalaxyConverter` (for round-trip validation)
- [ ] Test with IWC workflows

**Deliverables**:
- `workflow_abstraction.py` - Core data models
- `galaxy_converter.py` - Galaxy ↔ BUWF conversion
- Unit tests with IWC workflows

### Phase 2: Nextflow Integration (Week 2)

**Goal**: Add Nextflow support

- [ ] Implement `NextflowToUnifiedConverter`
  - Parse Nextflow DSL (regex-based initially)
  - Extract processes and workflow structure
  - Map to unified format
- [ ] Implement `UnifiedToNextflowConverter`
  - Generate Nextflow processes
  - Create workflow script
  - Generate config files
- [ ] Test with nf-core subworkflows

**Deliverables**:
- `nextflow_converter.py` - Nextflow ↔ BUWF conversion
- Integration tests with nf-core workflows

### Phase 3: Step Grouping Intelligence (Week 3)

**Goal**: Implement smart workflow step grouping

- [ ] Implement `WorkflowStepGrouper`
  - Pattern-based grouping
  - Use IWC analysis results
  - Annotation-based refinement
- [ ] Create grouping configuration from IWC analysis
- [ ] Test grouping on various workflow types

**Deliverables**:
- `workflow_grouper.py` - Step grouping logic
- `grouping_patterns.yaml` - Grouping configurations
- Evaluation report on grouping accuracy

### Phase 4: UI Integration (Week 4)

**Goal**: Build UI components for unified workflow presentation

- [ ] Create `WorkflowCanvas` component
- [ ] Create `HighLevelStepCard` component
- [ ] Create `DetailedStepCard` component
- [ ] Create `ParameterEditor` component
- [ ] Implement expand/collapse functionality
- [ ] Add workflow execution controls

**Deliverables**:
- Frontend components in `/frontend/client/src/components/workflow/`
- Integration with existing chat interface
- User documentation

### Phase 5: Nextflow Execution (Week 5-6)

**Goal**: Enable Nextflow execution on AWS Batch

- [ ] Implement `NextflowExecutor`
- [ ] Configure AWS Batch integration
- [ ] Set up S3 work directory
- [ ] Implement execution monitoring
- [ ] Test end-to-end workflow execution

**Deliverables**:
- `nextflow_executor.py` - Nextflow execution backend
- AWS infrastructure configuration
- Execution monitoring dashboard

---

## File Structure

```
backend/
├── lib/galaxy/ai/
│   ├── workflow_abstraction.py      # Core unified workflow models
│   ├── workflow_converters/
│   │   ├── __init__.py
│   │   ├── galaxy_converter.py      # Galaxy ↔ BUWF
│   │   ├── nextflow_converter.py    # Nextflow ↔ BUWF
│   │   └── base_converter.py        # Base converter interface
│   ├── workflow_grouper.py          # Step grouping logic
│   ├── workflow_executor/
│   │   ├── __init__.py
│   │   ├── galaxy_executor.py       # Galaxy execution
│   │   ├── nextflow_executor.py     # Nextflow execution
│   │   └── base_executor.py         # Base executor interface
│   └── grouping_patterns.yaml       # Grouping configurations

research/
├── scripts/
│   ├── test_galaxy_conversion.py    # Test Galaxy conversion
│   ├── test_nextflow_conversion.py  # Test Nextflow conversion
│   └── evaluate_grouping.py         # Evaluate grouping accuracy

frontend/
├── client/src/components/workflow/
│   ├── WorkflowCanvas.tsx           # Main workflow visualization
│   ├── HighLevelStepCard.tsx        # High-level step component
│   ├── DetailedStepCard.tsx         # Detailed step component
│   ├── ParameterEditor.tsx          # Parameter configuration
│   └── WorkflowExecutionPanel.tsx   # Execution controls
```

---

## Testing Strategy

### Unit Tests

1. **Conversion Tests**
   - Galaxy .ga → BUWF → Galaxy .ga (round-trip)
   - Nextflow .nf → BUWF → Nextflow .nf (round-trip)
   - Validate all workflow metadata preserved

2. **Grouping Tests**
   - Test pattern matching on known workflows
   - Validate group names and descriptions
   - Check ungrouped step handling

3. **Execution Tests**
   - Test workflow execution via Galaxy
   - Test workflow execution via Nextflow
   - Validate output consistency

### Integration Tests

1. **IWC Workflows** - Test all 105 workflows
2. **nf-core Workflows** - Test all 93 workflows
3. **Custom Workflows** - Test user-generated workflows

### Evaluation Metrics

1. **Conversion Accuracy** - % of workflows converted correctly
2. **Grouping Quality** - User evaluation of grouping clarity
3. **Execution Success Rate** - % of workflows that execute successfully
4. **Performance** - Conversion time, execution time

---

## Success Criteria

✅ All IWC workflows convert to unified format without errors
✅ All nf-core subworkflows convert to unified format
✅ Round-trip conversion preserves workflow semantics
✅ High-level step grouping makes sense to domain experts
✅ UI clearly presents workflow structure
✅ Galaxy execution works as before
✅ Nextflow execution works on AWS Batch
✅ Bidirectional conversion is lossless

---

## Future Enhancements

1. **ML-Based Grouping** - Train model on workflow collections
2. **Workflow Optimization** - Suggest improvements
3. **Multi-Cloud Support** - GCP, Azure execution
4. **Workflow Validation** - Scientific validity checks
5. **Parameter Recommendation** - Suggest parameters based on data

---

## References

- `20251119_1320_WORKFLOW_IMPROVEMENT_SUGGESTIONS.md` - IWC analysis and grouping patterns
- `20251119_1313_IWC_COMPREHENSIVE_ANALYSIS.md` - Tool usage patterns
- `WORKFLOW_INTEGRATION_ROADMAP.md` - Galaxy workflow integration strategy
- `NEXTFLOW_INTEGRATION.md` - Nextflow + AWS Batch integration
- `NEXTFLOW_ANALYSIS.md` - Nextflow file transfer mechanism

---

**Status**: Ready for Implementation
**Next Action**: Start Phase 1 - Core Abstraction Layer
