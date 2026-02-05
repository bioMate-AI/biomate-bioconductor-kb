# Galaxy_Nextflow Project Documentation

## Comprehensive Analysis: What galaxy_nextflow Adds to Original Galaxy

**Document Date**: 2026-02-03  
**Author**: AI Assistant  
**Purpose**: Document the unique features and modifications in the `galaxy_nextflow` project compared to the original Galaxy system

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Original Galaxy Overview](#original-galaxy-overview)
3. [Galaxy_Nextflow Additions](#galaxy_nextflow-additions)
   - [Nextflow Execution Engine](#1-nextflow-execution-engine)
   - [AI-Powered Operations (AI Ops)](#2-ai-powered-operations-ai-ops)
   - [AutoFix Framework](#3-autofix-framework)
   - [Workflow Converters](#4-workflow-converters)
   - [Cloud-Native Execution](#5-cloud-native-execution)
   - [Enhanced Monitoring](#6-enhanced-monitoring)
4. [Architecture Comparison](#architecture-comparison)
5. [File Structure Map](#file-structure-map)
6. [API Endpoints Added](#api-endpoints-added)
7. [Configuration Additions](#configuration-additions)
8. [Database Schema Additions](#database-schema-additions)

---

## Executive Summary

The `galaxy_nextflow` project extends the standard Galaxy bioinformatics platform with:

| Feature Category | What It Adds | Business Value |
|-----------------|--------------|----------------|
| **Nextflow Engine** | Execute workflows using Nextflow instead of Galaxy's native engine | Better scalability, cloud-native execution |
| **AI Operations** | LLM-powered log analysis, intelligent recommendations | Faster debugging, automated insights |
| **AutoFix Framework** | Automatic detection and repair of workflow failures | Reduced manual intervention, higher success rates |
| **Workflow Converters** | Bi-directional Galaxy ↔ Nextflow conversion | Workflow portability, ecosystem interoperability |
| **Cloud Execution** | AWS Batch, Slurm, Local execution support | Flexible deployment, cost optimization |
| **Enhanced Monitoring** | Real-time monitoring with CloudWatch integration | Better observability, faster issue detection |

---

## Original Galaxy Overview

### What Standard Galaxy Provides

Galaxy is an open-source platform for data-intensive biomedical research. The original Galaxy includes:

1. **Workflow Engine**: Step-by-step execution with `.ga` format workflows
2. **Tool Framework**: XML-based tool definitions with Python wrappers
3. **Job Runners**: Local, Slurm, PBS, Condor, Kubernetes runners
4. **Data Management**: History, datasets, libraries, collections
5. **User Interface**: Vue.js-based web interface
6. **API**: RESTful API for programmatic access
7. **Security**: User management, role-based access control

### Galaxy's Execution Model

```
User Request → Galaxy API → Workflow Engine → Job Runner → Local/HPC Execution
                                    ↓
                            Job State Management
                                    ↓
                            Output Collection
```

---

## Galaxy_Nextflow Additions

### 1. Nextflow Execution Engine

**Location**: `lib/galaxy/jobs/runners/`

#### Core Components

| File | Purpose | Lines of Code |
|------|---------|---------------|
| `nextflow_workflow_runner.py` | Main workflow job runner | ~2,800 |
| `nextflow_monitor.py` | Real-time workflow monitoring | ~1,700 |
| `nextflow_runner.py` | Single-task Nextflow runner | ~800 |
| `nextflow_s3_manager.py` | S3 data transfer management | ~600 |
| `nextflow_cloud_data_manager.py` | Cloud data lifecycle management | ~500 |
| `nextflow_batch_log_collector.py` | AWS CloudWatch log collection | ~700 |
| `nextflow_remote_executor.py` | Remote execution coordination | ~400 |
| `nextflow_tool_sync.py` | Tool synchronization | ~300 |

#### Key Features

**Multi-Executor Support**:
```yaml
# Supported executors
NEXTFLOW_EXECUTOR: awsbatch | local | slurm

# AWS Batch configuration
AWS_BATCH_QUEUE: galaxy-cloud-queue
AWS_DEFAULT_REGION: us-west-2
AWS_S3_BUCKET: my-bucket

# Slurm configuration  
SLURM_PARTITION: compute
SLURM_QOS: normal
SLURM_ACCOUNT: research_lab
```

**Execution Flow**:
```
Galaxy Workflow → GalaxyToNextflowConverter → Nextflow DSL2 Script
                                                    ↓
                                        NextflowWorkflowRunner
                                                    ↓
                          ┌─────────────────────────┼─────────────────────────┐
                          ↓                         ↓                         ↓
                     AWS Batch                   Local                     Slurm
                          ↓                         ↓                         ↓
                    CloudWatch                 Process                    squeue
                          ↓                         ↓                         ↓
                    S3 Storage              Local Storage           Shared FS
```

**S3 Transfer Modes**:
- `host-cli`: AWS CLI pre-installed in host AMI, mounted to containers
- `wave`: Seqera Wave container augmentation
- `fusion`: Nextflow Fusion filesystem

---

### 2. AI-Powered Operations (AI Ops)

**Location**: `lib/galaxy/ai/workflow_ops/`

#### Architecture

```
lib/galaxy/ai/workflow_ops/
├── __init__.py                      # Module exports
├── types.py                         # Data types (Issue, FixPlan, etc.)
├── llm_client.py                    # Unified LLM client (Anthropic/OpenAI/Ollama)
├── log_analyzer.py                  # Intelligent log analysis
├── auto_healer.py                   # Automatic error repair
├── query_agent.py                   # Natural language workflow queries
├── comprehensive_log_analyzer.py    # Multi-source log analysis
├── fix_applier.py                   # Apply fixes to system
├── analysis_persistence.py          # Store analysis results
└── models/                          # Pydantic models
```

#### Components

**UnifiedLLMClient** - Multi-provider LLM interface:
```python
# Supported providers
- Anthropic Claude (claude-3-5-sonnet, claude-3-haiku)
- OpenAI GPT (gpt-4o, gpt-4o-mini)
- Ollama (local models)

# Features
- Automatic cost calculation
- Budget control (daily/monthly limits)
- Retry logic with exponential backoff
- Usage statistics tracking
```

**WorkflowLogAnalyzer** - Tiered log analysis:
```python
# Analysis levels
1. Lightweight: Regex matching (INFO, progress) - FREE
2. Medium: Small model analysis (WARNING) - LOW COST
3. Heavy: Large model analysis (ERROR) - HIGH ACCURACY

# Output
LogAnalysisResult:
  - status: WorkflowStatus (running/warning/error/completed)
  - progress: ProgressInfo (current/total/percentage)
  - issues: List[Issue]
  - insights: str (LLM-generated natural language)
  - llm_cost: float
```

**WorkflowAutoHealer** - Automatic error repair:
```python
# Fix modes
- safe: Only low-risk operations (recommended for production)
- moderate: Low/medium risk operations
- aggressive: All operations (use carefully)
- manual: Requires user confirmation

# Supported fix types
- Parameter configuration errors
- Data format conversions
- Resource scaling
- Simple retries
```

**WorkflowQueryAgent** - Natural language interface:
```python
# Query types supported
- Error cause analysis
- Performance comparison
- Estimated completion time
- Historical run comparison

# Example
agent.query("Why did step 3 fail?", invocation_id=123)
→ "Step 3 (Alignment) failed because the reference genome 'hg19' 
   doesn't exist in the system. Recommend using 'hg38'."
```

#### Cost Estimation

| Operation | Input Tokens | Output Tokens | Cost |
|-----------|--------------|---------------|------|
| Log analysis (WARNING) | ~1000 | ~200 | ~$0.006 |
| Log analysis (ERROR) | ~2000 | ~500 | ~$0.014 |
| Error fix analysis | ~3000 | ~800 | ~$0.021 |
| Natural language query | ~1500 | ~300 | ~$0.009 |

**Recommended budget**: $5-10/day for moderate workloads

---

### 3. AutoFix Framework

**Location**: `lib/galaxy/ai/workflow_ops/autofix/`

#### Framework Architecture

```
lib/galaxy/ai/workflow_ops/autofix/
├── __init__.py                  # Framework entry
├── base.py                      # BaseAutoFixer abstract class
├── orchestrator.py              # AutoFixOrchestrator
├── validation.py                # Fix validation
├── workflow_restarter.py        # Automatic workflow restart
├── llm_parameter_mapper.py      # LLM-driven parameter mapping
└── fixers/
    ├── __init__.py
    ├── nextflow_parameter_fixer.py   # Parameter error fixing
    ├── data_file_fixer.py            # Data file issues
    ├── aws_resource_fixer.py         # AWS resource problems
    ├── retry_strategy_fixer.py       # Retry optimization
    ├── container_error_fixer.py      # Container errors
    ├── reference_genome_fixer.py     # Missing genome detection
    ├── file_format_fixer.py          # File format issues
    └── samplesheet_fixer.py          # Samplesheet validation
```

#### Core Concepts

**Risk-Based Approval**:
| Risk Level | Behavior | Examples |
|------------|----------|----------|
| LOW | Auto-approve if enabled | Typo fixes, format conversions |
| MEDIUM | Requires user click | Parameter value changes, resource adjustments |
| HIGH | Requires manual review + confirmation | AWS config changes, data deletion |

**BaseAutoFixer Interface**:
```python
class BaseAutoFixer(ABC):
    @abstractmethod
    def detect_issues(self, context: FixContext) -> List[Dict]:
        """Detect problems"""
        pass
    
    @abstractmethod
    def generate_fix_plan(self, context: FixContext, issues: List) -> FixPlan:
        """Generate repair plan"""
        pass
    
    @abstractmethod
    async def apply_fix(self, context: FixContext, fix_plan: FixPlan, sa_session) -> AutoFixResult:
        """Execute repair"""
        pass
```

**LLM-Driven Parameter Mapping** (v2.0):
```python
# Zero-config startup - adapts to any pipeline automatically
mapper = LLMParameterMapper(llm_client=llm_client, enable_learning=True)

# Maps conceptual parameters to actual pipeline format
mapped = mapper.map_fix_params(
    pipeline_name='any_pipeline',
    fix_params={'sensitivity': 'high', 'max_reads': '1M'},
    pipeline_schema=auto_extracted_schema,
    workflow_config=current_config
)

# First mapping: ~3 seconds, ~$0.005 (LLM inference)
# Subsequent mappings: <10ms, $0 (cached)
```

#### Built-in Fixers

1. **NextflowParameterFixer** - Missing/invalid parameter detection
   - Value inference from historical runs
   - Template defaults lookup
   - Pipeline-specific defaults

2. **ContainerErrorFixer** - Docker/container issues
   - Parse `workflow-trace.txt`
   - Classify error types (GTF_FORMAT, STAR_INDEX, etc.)
   - Provide targeted recommendations

3. **ReferenceGenomeFixer** - Missing genome detection
   - Detect unavailable reference genomes
   - Provide download/index build solutions

4. **FileFormatFixer** - File format problems
   - FASTQ encoding issues
   - Line ending problems
   - BOM detection

5. **AWSResourceFixer** - Cloud resource issues
   - Instance type recommendations
   - Memory/CPU scaling suggestions

6. **RetryStrategyFixer** - Retry optimization
   - Transient error detection
   - Retry configuration adjustment

---

### 4. Workflow Converters

**Location**: `lib/galaxy/workflow/converters/`

#### Bi-directional Conversion

```
Galaxy .ga Format ←→ Nextflow DSL2 Format
        ↓                    ↓
GalaxyToNextflowConverter    NextflowToGalaxyConverter
        ↓                    ↓
    main.nf              workflow.ga
    nextflow.config      tool definitions
    subworkflows/        step mappings
```

#### GalaxyToNextflowConverter

**Purpose**: Export Galaxy workflows as independent Nextflow workflows

```python
converter = GalaxyToNextflowConverter(app)
result = converter.convert_workflow('workflow.ga')

# Output
{
    'nextflow_script': 'main.nf content',
    'config': 'nextflow.config content',
    'subworkflows': {'sub1': 'subworkflow content'},
    'metadata': {
        'source': 'workflow.ga',
        'workflow_name': 'My Workflow',
        'step_count': 10,
        'galaxy_metadata': {...}
    }
}
```

#### NextflowToGalaxyConverter

**Purpose**: Import nf-core and other Nextflow workflows into Galaxy

```python
converter = NextflowToGalaxyConverter(app)
result = converter.convert_workflow('main.nf')

# Output
{
    'success': True,
    'galaxy_workflow': {...},  # Galaxy .ga format
    'tools': [...]  # Generated Galaxy tool definitions
}
```

**Challenges Addressed**:
- Nextflow is code-style, Galaxy is config-style
- Complex channel operations → explicit step connections
- Process wrapping as Galaxy tools

#### Additional Converters

| File | Purpose |
|------|---------|
| `nextflow_pipeline_importer.py` | Import complete nf-core pipelines |
| `nextflow_pipeline_importer_enhanced.py` | Enhanced import with validation |
| `nextflow_schema_parser.py` | Parse `nextflow_schema.json` |
| `nextflow_tool_generator.py` | Generate Galaxy tool XML |
| `universal_nextflow_param_extractor.py` | Extract parameters from any pipeline |

---

### 5. Cloud-Native Execution

**Location**: `lib/galaxy/galaxy-cloud-executor/`

#### Architecture

```
Galaxy → Nextflow Runner → Executor (AWS Batch/Slurm/Local)
                ↓
         S3 Data Manager
                ↓
         CloudWatch Logs
                ↓
         Output Sync to Galaxy
```

#### Cloud Data Manager

```python
class CloudDataManager:
    """Manages cloud-native data lifecycle"""
    
    # Input handling
    def upload_inputs_to_s3(inputs) → s3_uris
    
    # Output handling
    def sync_outputs_to_galaxy(s3_uris) → galaxy_datasets
    
    # Reference data
    def resolve_reference_data(genome) → s3_path
```

#### Features

1. **Cloud-Native Mode**: Data stays in S3, never downloads to Galaxy server
2. **Hybrid Mode**: Download outputs to Galaxy for local access
3. **Reference Data**: Pre-staged reference genomes in S3
4. **Cost Optimization**: Spot instances, preemptible VMs

---

### 5.1 Galaxy Data Management & Visualization Continuity

**Goal**: Preserve Galaxy's built-in data source management, data manipulation, uploads, and interactive visualization while executing workflows in Nextflow.

**How it stays intact**:
- **Single History**: Nextflow runs are still tracked as Galaxy workflow invocations with a **Galaxy history**.
- **Dataset registration**: Outputs are synchronized into Galaxy histories, enabling Galaxy's native dataset metadata and visualization.
- **Upload and provenance**: Data uploads and dataset provenance remain Galaxy-native; Nextflow only changes execution.

**Soft fallback policy (outputs)**:
- **Primary path**: Fetch outputs from the Galaxy history created for the invocation.
- **Fallback**: If history resolution is missing or outputs are not present, re-resolve the actual history ID via the Galaxy invocation record, then fetch again.
- **Avoid divergence**: Only introduce Nextflow filesystem reads if Galaxy history sync is provably unavailable.

### 6. Enhanced Monitoring

**Location**: `lib/galaxy/jobs/runners/nextflow_monitor.py`

#### NextflowMonitor

```python
class NextflowMonitor:
    """
    Single workflow monitor with:
    1. Real-time log streaming to Galaxy
    2. Status polling and updates
    3. Output synchronization
    4. AWS Batch log collection (CloudWatch)
    5. LLM intelligent log analysis (NEW)
    6. Automatic error repair (NEW)
    """
    
    def __init__(self, invocation_id, work_dir, process_pid, app,
                 enable_batch_logs=True, enable_ai_ops=True):
        # Initialize monitoring components
        
    def monitor_once(self):
        """Single monitoring cycle"""
        logs = self.collect_logs()
        
        if self.log_analyzer:
            result = self.log_analyzer.analyze_logs_stream(logs)
            
            if result.issues:
                self.auto_healer.analyze_and_fix(...)
```

#### Log Sources

```
┌─────────────────────────────────────────────────────────────┐
│                    Three-Source Log Analysis                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Galaxy Server Logs          Nextflow Logs                  │
│  - gunicorn.log              - .nextflow.log                │
│  - handler_*.log             - nextflow.out/err             │
│                              - workflow-trace.txt           │
│                                                             │
│                    AWS Batch Logs                           │
│                    - CloudWatch                             │
│                    - Task exit codes                        │
│                    - Resource utilization                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Architecture Comparison

### Original Galaxy

```
┌──────────────────────────────────────────────────────────────┐
│                        Galaxy Server                          │
├──────────────────────────────────────────────────────────────┤
│  Web UI (Vue.js)  │  REST API (FastAPI)                      │
├───────────────────┴──────────────────────────────────────────┤
│                    Workflow Engine                            │
│                    - Step-by-step execution                   │
│                    - .ga format workflows                     │
├──────────────────────────────────────────────────────────────┤
│                    Job Runners                                │
│                    - Local, Slurm, PBS, Condor, K8s          │
├──────────────────────────────────────────────────────────────┤
│                    Data Management                            │
│                    - Histories, Datasets, Libraries          │
└──────────────────────────────────────────────────────────────┘
```

### Galaxy_Nextflow

```
┌──────────────────────────────────────────────────────────────┐
│                   Galaxy + Nextflow Server                    │
├──────────────────────────────────────────────────────────────┤
│  Web UI (Vue.js)  │  REST API (FastAPI)                      │
│  + AI Ops Dashboard (NEW)                                     │
├───────────────────┴──────────────────────────────────────────┤
│                    Workflow Engine                            │
│                    - Galaxy native execution                  │
│                    - Nextflow DSL2 execution (NEW)           │
│                    - Bi-directional conversion (NEW)         │
├──────────────────────────────────────────────────────────────┤
│                    Job Runners                                │
│                    - Original: Local, Slurm, PBS, Condor, K8s│
│                    - NEW: NextflowWorkflowRunner             │
│                    - NEW: AWS Batch, Cloud-native            │
├──────────────────────────────────────────────────────────────┤
│                    AI Operations (NEW)                        │
│                    - LLM Log Analysis                        │
│                    - AutoFix Framework                       │
│                    - Natural Language Queries                │
├──────────────────────────────────────────────────────────────┤
│                    Enhanced Monitoring (NEW)                  │
│                    - Real-time Nextflow monitoring           │
│                    - CloudWatch integration                   │
│                    - Multi-source log analysis               │
├──────────────────────────────────────────────────────────────┤
│                    Data Management                            │
│                    - Histories, Datasets, Libraries          │
│                    - S3 Cloud Data Manager (NEW)             │
└──────────────────────────────────────────────────────────────┘
```

---

## File Structure Map

### New Directories Added

```
lib/galaxy/
├── ai/                                    # NEW - AI/LLM modules
│   └── workflow_ops/                      # NEW - Workflow AI operations
│       ├── autofix/                       # NEW - AutoFix framework
│       │   └── fixers/                    # NEW - Built-in fixers
│       └── models/                        # NEW - Pydantic models
│
├── jobs/runners/
│   ├── nextflow_*.py                      # NEW - 9 Nextflow runner files
│   ├── biocontainer_resolver.py           # NEW - Container resolution
│   ├── smart_container_resolver.py        # NEW - Smart resolution
│   └── unified_container_resolver.py      # NEW - Unified resolver
│
├── workflow/
│   ├── converters/                        # NEW - Workflow converters
│   │   ├── galaxy_to_nextflow_converter.py
│   │   ├── nextflow_to_galaxy_converter.py
│   │   ├── nextflow_pipeline_importer.py
│   │   ├── nextflow_schema_parser.py
│   │   └── nextflow_tool_generator.py
│   │
│   └── schedulers/
│       └── nextflow.py                    # NEW - Nextflow scheduler
│
├── galaxy-cloud-executor/                 # NEW - Cloud execution
│   └── galaxy_cloud/
│       └── galaxy_workflow/
│           ├── nextflow_executor.py
│           └── nextflow_converter.py
│
└── webapps/galaxy/api/
    ├── workflow_ai_ops.py                 # NEW - AI ops API (~6000 lines)
    ├── workflow_ai_ops_detailed.py        # NEW - Detailed analysis API
    ├── workflow_ai_realtime.py            # NEW - Real-time API
    ├── autofix3.py                        # NEW - AutoFix API
    └── workflow_converters.py             # NEW - Converter API
```

### Documentation Files

```
galaxy_nextflow/
├── INTEGRATION_SUMMARY.md                 # AutoFix integration summary
├── AI_OPS_ENHANCED_SYSTEM_SUMMARY.md      # AI Ops system overview
├── AUTOFIX_FINAL_SUMMARY.md               # AutoFix framework summary
├── docs/
│   ├── WORKFLOW_AI_OPS_QUICKSTART.md      # Quick start guide
│   └── NEXTFLOW_EXECUTOR_CONFIGURATION.md # Executor configuration
└── lib/galaxy/ai/workflow_ops/
    ├── README.md                          # Workflow ops documentation
    └── autofix/README.md                  # AutoFix documentation
```

---

## API Endpoints Added

### AI Operations Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/workflows/{id}/ai/analyze` | POST | Analyze workflow with LLM |
| `/api/workflows/{id}/ai/analyze_detailed` | POST | Detailed multi-source analysis |
| `/api/workflows/{id}/ai/query` | POST | Natural language query |
| `/api/workflows/{id}/ai/auto_fix` | POST | Trigger auto-fix |
| `/api/workflows/{id}/ai/budget` | GET | Budget usage statistics |
| `/api/workflows/{id}/ai/analysis_history` | GET | Historical analyses |
| `/api/workflows/{id}/ai/apply_fix` | POST | Apply specific fix |

### AutoFix Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/workflows/{id}/autofix/run` | POST | Run AutoFix orchestrator |
| `/api/workflows/{id}/autofix/audit_logs` | GET | View audit logs |
| `/api/workflows/{id}/autofix/approve/{fix_id}` | POST | Approve pending fix |

### Workflow Converter Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/workflows/convert/galaxy-to-nextflow` | POST | Convert Galaxy to Nextflow |
| `/api/workflows/convert/nextflow-to-galaxy` | POST | Convert Nextflow to Galaxy |
| `/api/workflows/import/nfcore` | POST | Import nf-core pipeline |

---

## Configuration Additions

### Environment Variables

```bash
# Nextflow Executor
NEXTFLOW_EXECUTOR=awsbatch|local|slurm

# AWS Configuration
AWS_BATCH_QUEUE=galaxy-cloud-queue
AWS_DEFAULT_REGION=us-west-2
AWS_S3_BUCKET=my-bucket
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...

# Slurm Configuration
SLURM_PARTITION=compute
SLURM_QOS=normal
SLURM_ACCOUNT=my_account

# AI Operations
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
NEXTFLOW_AI_DAILY_BUDGET=10.0
NEXTFLOW_AUTO_FIX_MODE=safe|moderate|aggressive|manual
NEXTFLOW_ENABLE_AI_OPS=true|false

# Cloud-Native Mode
NEXTFLOW_CLOUD_NATIVE=true|false

# S3 Transfer Mode
NEXTFLOW_S3_TRANSFER_MODE=host-cli|wave|fusion
```

### Galaxy Configuration (galaxy.yml)

```yaml
gravity:
  environment:
    # Nextflow Executor
    NEXTFLOW_EXECUTOR: awsbatch
    
    # AWS Batch
    AWS_BATCH_QUEUE: galaxy-cloud-queue
    AWS_DEFAULT_REGION: us-west-2
    AWS_S3_BUCKET: galaxy-data
    
    # Nextflow Features
    NEXTFLOW_ENABLE_WAVE: 'false'
    NEXTFLOW_ENABLE_FUSION: 'false'
    
    # AI Operations
    NEXTFLOW_AI_DAILY_BUDGET: '10.0'
    NEXTFLOW_AUTO_FIX_MODE: 'safe'
```

---

## Database Schema Additions

### AIFixAuditLog Table

```sql
CREATE TABLE ai_fix_audit_log (
    id INTEGER PRIMARY KEY,
    invocation_id INTEGER REFERENCES workflow_invocation(id),
    user_id INTEGER REFERENCES galaxy_user(id),
    
    -- Fix details
    fix_type VARCHAR(50),           -- parameter/resource/container/etc
    fixer_name VARCHAR(100),
    risk_level VARCHAR(20),         -- LOW/MEDIUM/HIGH
    
    -- Approval status
    auto_approved BOOLEAN,
    user_approved BOOLEAN,
    applied BOOLEAN,
    success BOOLEAN,
    
    -- Details (JSON)
    fix_details JSON,               -- Full fix plan
    applied_changes JSON,           -- What was changed
    error_details JSON,             -- Error info if failed
    
    -- AI metadata
    ai_model_used VARCHAR(100),
    ai_confidence FLOAT,
    
    -- Cost tracking
    estimated_cost FLOAT,
    actual_cost FLOAT,
    
    -- Timing
    create_time TIMESTAMP,
    duration_seconds FLOAT
);

CREATE INDEX idx_ai_fix_user ON ai_fix_audit_log(user_id);
CREATE INDEX idx_ai_fix_invocation ON ai_fix_audit_log(invocation_id);
CREATE INDEX idx_ai_fix_time ON ai_fix_audit_log(create_time);
```

### UserCloudPreferences Table

```sql
CREATE TABLE user_cloud_preferences (
    id INTEGER PRIMARY KEY,
    user_id INTEGER REFERENCES galaxy_user(id),
    
    -- AI preferences
    ai_require_approval_for_cost FLOAT,  -- Cost threshold for approval
    ai_daily_budget FLOAT,
    ai_auto_approve_low_risk BOOLEAN,
    
    -- Cloud preferences
    preferred_executor VARCHAR(50),
    aws_instance_preference VARCHAR(100),
    
    -- Timestamps
    create_time TIMESTAMP,
    update_time TIMESTAMP
);
```

---

## Frontend UI Components Added

The `galaxy_nextflow` project adds significant UI components to the standard Galaxy Vue.js frontend, providing visual interfaces for AI operations, Nextflow monitoring, and workflow management.

### New Vue Components Overview

**Location**: `client/src/components/`

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| **WorkflowAIOpsIndustrial** | `Workflow/WorkflowAIOpsIndustrial.vue` | ~860 | Industrial-grade AI ops dashboard |
| **WorkflowAIOpsEnhanced** | `Workflow/WorkflowAIOpsEnhanced.vue` | ~3,000 | Enhanced AI operations panel |
| **WorkflowAIOps** | `Workflow/WorkflowAIOps.vue` | ~980 | Basic AI ops control panel |
| **WorkflowAIMonitor** | `Workflow/WorkflowAIMonitor.vue` | ~870 | AI monitoring with stages |
| **WorkflowAIOpsFriendly** | `Workflow/WorkflowAIOpsFriendly.vue` | ~450 | User-friendly AI ops view |
| **AIAssistant** | `AI/AIAssistant.vue` | ~1,040 | Full AI chat interface |
| **AIAssistantPanel** | `AI/AIAssistantPanel.vue` | ~1,600 | Sliding AI assistant panel |
| **FromNextflow** | `Workflow/Import/FromNextflow.vue` | ~230 | Nextflow workflow import UI |
| **WorkflowAgentDashboard** | `Workflow/WorkflowAgentDashboard.vue` | ~500 | Agent management dashboard |
| **AgentDiagnosisPanel** | `Workflow/AgentDiagnosisPanel.vue` | ~400 | Issue diagnosis interface |
| **AgentStatsPanel** | `Workflow/AgentStatsPanel.vue` | ~350 | Agent statistics display |
| **WorkflowStage** | `Workflow/WorkflowStage.vue` | ~200 | Stage-based workflow progress |
| **WorkflowParametersTable** | `Workflow/WorkflowParametersTable.vue` | ~300 | Parameter visualization |
| **WorkflowWizard** | `Workflow/Run/WorkflowWizard.vue` | ~550 | AI-guided workflow setup |

---

### Component Details

#### 1. WorkflowAIOpsIndustrial (Industrial Dashboard)

**File**: `client/src/components/Workflow/WorkflowAIOpsIndustrial.vue`

**Purpose**: Production-grade AI operations dashboard with comprehensive monitoring and control.

**Key Features**:
- **Metric Cards**: Health score, active issues, success rate, running costs
- **Analysis Progress Stepper**: Visual step-by-step analysis progress
- **Root Cause Analysis Panel**: Detailed error investigation with evidence
- **Three-Source Log Analysis**: Tabbed view of Galaxy/Nextflow/AWS Batch logs
- **Recommendations Panel**: AI-generated fix suggestions with one-click apply

**UI Layout**:
```
┌─────────────────────────────────────────────────────────────────┐
│  🩺 Health    ⚠️ Issues    ✅ Success%    💰 Cost              │
│     Score       Count         Rate          Total               │
├─────────────────────────────────────────────────────────────────┤
│  🔍 AI Analysis Progress                                        │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐                                │
│  │ 1 │→│ 2 │→│ 3 │→│ 4 │→│ 5 │  (Connect → Analyze → Detect  │
│  └───┘ └───┘ └───┘ └───┘ └───┘   → Fix → Complete)            │
├─────────────────────────────────────────────────────────────────┤
│  ⚠️ Root Cause Analysis                                        │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ [CRITICAL] GTF Format Error                              │   │
│  │ Evidence: iCount failed to parse GTF                     │   │
│  │ Confidence: 95%  │  Affected Tasks: 30                   │   │
│  └─────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│  📊 Three-Source Log Analysis                                  │
│  ┌────────────────┬────────────────┬────────────────┐         │
│  │ Galaxy Server  │ Nextflow       │ AWS Batch      │         │
│  │ (3 errors)     │ (5 errors)     │ (2 errors)     │         │
│  └────────────────┴────────────────┴────────────────┘         │
├─────────────────────────────────────────────────────────────────┤
│  💡 Intelligent Recommendations                                │
│  [1] Add --skip_filter_gtf parameter     [Auto Apply] [Skip]   │
│  [2] Increase memory to 32GB             [Approve]    [Skip]   │
└─────────────────────────────────────────────────────────────────┘
```

**Backend Connections**:
```javascript
// Detailed analysis with multi-source logs
POST `/api/workflows/${invocationId}/ai/analyze_detailed`

// Apply recommended fix
POST `/api/workflows/${invocationId}/ai/apply_fix`
  Body: { recommendation_id, auto_confirm }
```

---

#### 2. WorkflowAIOpsEnhanced (Enhanced Operations)

**File**: `client/src/components/Workflow/WorkflowAIOpsEnhanced.vue`

**Purpose**: Comprehensive AI operations with Nextflow-specific monitoring and AutoFix integration.

**Key Features**:
- **Nextflow Real-time Monitor**: Task progress, success/failure counts
- **Error Summary Cards**: Quick view of detected errors
- **AutoFix Integration**: One-click automated repair
- **Parameter Analysis**: Visual parameter configuration review
- **Resource Optimization**: AI-suggested resource adjustments
- **Agent Management**: Toggle and monitor AI agents

**UI Layout**:
```
┌─────────────────────────────────────────────────────────────────┐
│  🤖 AI 智能运维中心                                             │
│  Nextflow · AWS Batch · 自动诊断 · 智能修复                     │
├─────────────────────────────────────────────────────────────────┤
│  [═══════════════════════════75%═══════════════════]           │
├─────────────────────────────────────────────────────────────────┤
│  📊 主监控  │  🔧 参数配置  │  📈 资源优化  │  🤖 Agent管理      │
├─────────────────────────────────────────────────────────────────┤
│  🔄 Nextflow 实时监控                          [刷新]          │
│  ┌──────────┬──────────┬──────────┬──────────┐                │
│  │ 总任务数  │ 已完成   │ 运行中   │ 失败     │                │
│  │    150   │   120    │    5     │   25     │                │
│  └──────────┴──────────┴──────────┴──────────┘                │
│                                                                 │
│  [═════════════════════════80%═════════════════════]           │
│                                                                 │
│  ❌ 检测到 3 个错误                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ [ERROR] GTF Format Error - iCount failed...              │   │
│  │ 💡 建议: 添加 --skip_filter_gtf 参数                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  [🤖 运行 AutoFix 自动修复]   [查看新 Workflow]                 │
└─────────────────────────────────────────────────────────────────┘
```

**Backend Connections**:
```javascript
// Get workflow info
GET `/api/workflows/${invocationId}/ai/info`

// Analyze parameters
POST `/api/workflows/${invocationId}/ai/analyze_parameters`

// Detailed analysis
POST `/api/workflows/${invocationId}/ai/analyze_detailed`

// Dispatch to specific agent
POST `/api/workflows/${invocationId}/ai/agent/dispatch`
  Body: { type, message }

// Apply fix
POST `/api/workflows/${invocationId}/ai/apply_fix`
  Body: { fix_action, fix_params, auto_confirm }

// Analyze resources
POST `/api/workflows/${invocationId}/ai/analyze_resources`

// Agent management
GET `/api/ai/agents/list`
POST `/api/ai/agents/${agentName}/toggle`
  Body: { enabled }

// Save/Load analysis
POST `/api/workflows/${invocationId}/ai/save_analysis`
GET `/api/workflows/${invocationId}/ai/load_analysis`
```

---

#### 3. AIAssistant (Chat Interface)

**File**: `client/src/components/AI/AIAssistant.vue`

**Purpose**: Full-featured chat interface for natural language interaction with Galaxy AI.

**Key Features**:
- **Chat Messages**: User/AI conversation display
- **Intent Detection**: Shows detected intent and confidence
- **Task Decomposition**: Displays analysis steps
- **Tool Recommendations**: Lists recommended tools with reasoning
- **Workflow Generation**: Creates workflows from descriptions
- **Execution Plans**: Shows planned execution steps
- **Context Panel**: Available datasets and recent workflows

**UI Layout**:
```
┌─────────────────────────────────────────────────────────────────┐
│  🤖 Galaxy AI Assistant                    ● Connected          │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ You: Analyze differential gene expression from RNA-seq    │ │
│  │ ─────────────────────────────────────────────────────────│ │
│  │ AI Assistant:                                             │ │
│  │                                                           │ │
│  │ 📌 Detected Intent: rna_seq_analysis (95% confidence)    │ │
│  │                                                           │ │
│  │ 📋 Analysis Steps:                                        │ │
│  │   1. Quality Control - FastQC                            │ │
│  │   2. Adapter Trimming - Trim Galore                      │ │
│  │   3. Alignment - STAR                                     │ │
│  │   4. Quantification - featureCounts                      │ │
│  │   5. Differential Analysis - DESeq2                      │ │
│  │                                                           │ │
│  │ 🔧 Recommended Tools:                                     │ │
│  │   • FastQC (98%) - Quality metrics                       │ │
│  │   • STAR (95%) - Splice-aware alignment                  │ │
│  │   • DESeq2 (92%) - Statistical analysis                  │ │
│  │                                                           │ │
│  │ 📊 Generated Workflow: RNA-seq Analysis Pipeline         │ │
│  │   5 steps | [Create Workflow] [Preview]                  │ │
│  └───────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│  [Describe your research needs...                    ] [Send]  │
│  Press Ctrl+Enter to send                                       │
└─────────────────────────────────────────────────────────────────┘
```

---

#### 4. AIAssistantPanel (Sliding Panel)

**File**: `client/src/components/AI/AIAssistantPanel.vue`

**Purpose**: Collapsible side panel for quick AI access from anywhere in Galaxy.

**Key Features**:
- **Toggle Button**: Always visible robot icon
- **Quick Actions**: One-click common analysis types
- **Compact Chat**: Streamlined conversation interface
- **Notification Badge**: Unread message indicator
- **Expand Option**: Link to full AI interface

**UI Layout**:
```
┌────┐
│ 🤖 │ ← Toggle button (always visible)
└────┘
    ↓ (when open)
┌─────────────────────────────┐
│ AI Assistant            ✕  │
├─────────────────────────────┤
│ Quick Start                 │
│ [🧬 RNA-seq] [🔍 Variant]  │
│ [🧩 Assembly] [✓ QC]       │
├─────────────────────────────┤
│ Ask AI Assistant            │
│ ┌─────────────────────────┐│
│ │ Hello! I can help you:  ││
│ │ • Design workflows      ││
│ │ • Recommend tools       ││
│ │ • Explain steps         ││
│ └─────────────────────────┘│
├─────────────────────────────┤
│ [Type your question...  📤]│
├─────────────────────────────┤
│ ● AI Ready            [⬜] │
└─────────────────────────────┘
```

---

#### 5. FromNextflow (Import UI)

**File**: `client/src/components/Workflow/Import/FromNextflow.vue`

**Purpose**: Import Nextflow workflows and convert to Galaxy format.

**Key Features**:
- **File Upload**: Accept `.nf` files and ZIP archives
- **Auto-naming**: Extract workflow name from filename
- **Pipeline Import**: Full nf-core pipeline support with auto-workflow generation
- **DSL Conversion**: Convert Nextflow DSL2 to Galaxy format
- **Subworkflow Support**: Import included workflows

**Backend Connections**:
```javascript
// Import nf-core pipeline (ZIP)
POST `/api/nextflow/pipelines/import`
  FormData: { pipeline_file, pipeline_name, auto_generate_workflow, run_test }

// Convert .nf file
POST `/api/workflows/import/nextflow`
  FormData: { nextflow_file, workflow_name, publish }
```

---

#### 6. WorkflowAIMonitor (Stage-based Monitor)

**File**: `client/src/components/Workflow/WorkflowAIMonitor.vue`

**Purpose**: Step-by-step AI monitoring with clear stage progression.

**Key Features**:
- **Mode Selection**: Full-auto vs manual confirmation
- **5-Stage Progress**: Connect → Analyze → Detect → Fix → Complete
- **Parameters Table**: Visual parameter configuration
- **Chat Assistant**: Always-available AI Q&A
- **History Persistence**: Save and load analysis sessions

**Backend Connections**:
```javascript
// Get workflow info
GET `/api/workflows/${invocationId}/ai/info`

// Full analysis
POST `/api/workflows/${invocationId}/ai/analyze`
  Body: { analysis_type: 'full', include_suggestions: true }

// Apply fix
POST `/api/workflows/${invocationId}/ai/apply_fix`
  Body: { fix_action, fix_params, user_approved }

// Natural language query
POST `/api/workflows/${invocationId}/ai/query`
  Body: { question, chat_history }

// Chat history
GET `/api/workflows/${invocationId}/ai/history`
POST `/api/workflows/${invocationId}/ai/history/save`
  Body: { chat_history, analysis_state }
```

---

#### 7. WorkflowInvocationState Integration

**File**: `client/src/components/WorkflowInvocationState/WorkflowInvocationState.vue`

**Purpose**: Extended standard workflow invocation view with AI Ops tab.

**Modification**: Added `ai-ops` tab option and integrated `WorkflowAIOpsEnhanced` component.

```typescript
// Tab options now include 'ai-ops'
interface Props {
    tab?: "steps" | "inputs" | "outputs" | "report" | "export" | "metrics" | "debug" | "ai-ops";
}

// Import and use AI ops component
import WorkflowAIOpsEnhanced from "../Workflow/WorkflowAIOpsEnhanced.vue";
```

---

### Frontend-Backend API Connection Map

#### AI Operations APIs

| Frontend Action | API Endpoint | Method | Request Body | Response |
|----------------|--------------|--------|--------------|----------|
| Start AI analysis | `/api/workflows/{id}/ai/analyze` | POST | `{analysis_type, include_suggestions}` | `{status, issues, insights}` |
| Detailed analysis | `/api/workflows/{id}/ai/analyze_detailed` | POST | `{}` | `{root_causes, logs, recommendations}` |
| Get workflow info | `/api/workflows/{id}/ai/info` | GET | - | `{workflow, state, parameters}` |
| Apply fix | `/api/workflows/{id}/ai/apply_fix` | POST | `{fix_action, fix_params}` | `{success, applied_changes}` |
| Natural language query | `/api/workflows/{id}/ai/query` | POST | `{question, chat_history}` | `{answer, confidence, sources}` |
| Parameter analysis | `/api/workflows/{id}/ai/analyze_parameters` | POST | `{}` | `{parameters, issues, recommendations}` |
| Resource analysis | `/api/workflows/{id}/ai/analyze_resources` | POST | `{}` | `{usage, optimization_suggestions}` |
| Save analysis | `/api/workflows/{id}/ai/save_analysis` | POST | `{analysis_data, is_final}` | `{success}` |
| Load analysis | `/api/workflows/{id}/ai/load_analysis` | GET | - | `{has_data, analysis_data}` |

#### Agent Management APIs

| Frontend Action | API Endpoint | Method | Request Body | Response |
|----------------|--------------|--------|--------------|----------|
| List agents | `/api/ai/agents/list` | GET | - | `{agents: [...]}` |
| Toggle agent | `/api/ai/agents/{name}/toggle` | POST | `{enabled}` | `{success}` |
| Agent dashboard | `/api/ai/agents/dashboard` | GET | - | `{stats, recent_activity}` |
| Dispatch to agent | `/api/workflows/{id}/ai/agent/dispatch` | POST | `{type, message}` | `{agent_response, fix_suggestions}` |

#### Workflow Run APIs

| Frontend Action | API Endpoint | Method | Request Body | Response |
|----------------|--------------|--------|--------------|----------|
| Wizard config | `/api/workflows/{id}/ai/wizard_config` | GET | - | `{pipeline_type, parameters, schema}` |
| Samplesheet template | `/api/workflows/{id}/ai/samplesheet_template` | GET | - | Blob (CSV file) |
| Validate parameters | `/api/workflows/{id}/ai/validate_parameters` | POST | `{parameters}` | `{valid, errors, warnings}` |
| Recommend parameters | `/api/workflows/{id}/ai/recommend_parameters` | POST | `{current_parameters}` | `{recommendations}` |
| Parameter metadata | `/api/workflows/{id}/ai/parameter_metadata` | GET | - | `{schema, defaults, descriptions}` |

#### Nextflow Import APIs

| Frontend Action | API Endpoint | Method | Request Body | Response |
|----------------|--------------|--------|--------------|----------|
| Import pipeline (ZIP) | `/api/nextflow/pipelines/import` | POST | FormData | `{workflow_generated, message}` |
| Import workflow (.nf) | `/api/workflows/import/nextflow` | POST | FormData | `{id, message, subworkflow_count}` |

---

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                          User Interface                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────┐  │
│  │ WorkflowAIOps   │  │ AIAssistant     │  │ FromNextflow        │  │
│  │ Industrial/     │  │ Panel           │  │ Import              │  │
│  │ Enhanced        │  │                 │  │                     │  │
│  └────────┬────────┘  └────────┬────────┘  └──────────┬──────────┘  │
│           │                    │                       │             │
└───────────┼────────────────────┼───────────────────────┼─────────────┘
            │ axios              │ axios                 │ axios
            ↓                    ↓                       ↓
┌───────────────────────────────────────────────────────────────────────┐
│                         REST API Layer                                 │
│                                                                        │
│  /api/workflows/{id}/ai/*     /api/ai/agents/*    /api/nextflow/*     │
│  ├── analyze                  ├── list            ├── pipelines/import│
│  ├── analyze_detailed         ├── toggle          └── convert         │
│  ├── apply_fix                └── dashboard                           │
│  ├── query                                                            │
│  └── info                                                             │
│                                                                        │
└───────────────────────────────────────────────────────────────────────┘
                                    │
                                    ↓
┌───────────────────────────────────────────────────────────────────────┐
│                         Backend Services                               │
│                                                                        │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │
│  │ workflow_ai_ops  │  │ AutoFix          │  │ Workflow Converters  │ │
│  │ .py              │  │ Orchestrator     │  │                      │ │
│  │                  │  │                  │  │ Galaxy ↔ Nextflow    │ │
│  │ - LogAnalyzer    │  │ - 8 Fixers       │  │                      │ │
│  │ - QueryAgent     │  │ - Risk Eval      │  │                      │ │
│  │ - AutoHealer     │  │ - Audit Log      │  │                      │ │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘ │
│                                                                        │
└───────────────────────────────────────────────────────────────────────┘
                                    │
                                    ↓
┌───────────────────────────────────────────────────────────────────────┐
│                    External Services & Storage                         │
│                                                                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │ LLM APIs    │  │ AWS Batch   │  │ CloudWatch  │  │ S3 Storage  │  │
│  │ (Anthropic/ │  │ (Execution) │  │ (Logs)      │  │ (Data)      │  │
│  │  OpenAI)    │  │             │  │             │  │             │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │
│                                                                        │
└───────────────────────────────────────────────────────────────────────┘
```

---

### UI State Management

The frontend components use Vue.js reactive state with the following patterns:

```javascript
// Component state structure (typical)
{
  // Status flags
  isRunning: false,
  isCompleted: false,
  loading: false,
  
  // Workflow data
  invocationId: string,
  workflowInfo: { name, state, parameters },
  
  // Analysis results
  analysisResult: { summary, root_causes, recommendations },
  detectedIssues: [],
  proposedFixes: [],
  
  // Nextflow specific
  nextflowStatus: {
    totalTasks: 0,
    completedTasks: 0,
    runningTasks: 0,
    failedTasks: 0,
    progressPercent: 0
  },
  
  // AI/LLM tracking
  llmCallCount: 0,
  totalCost: 0,
  
  // Chat state
  chatMessages: [],
  queryText: ''
}
```

---

## Summary

The `galaxy_nextflow` project transforms Galaxy from a traditional step-by-step workflow platform into a modern, AI-powered, cloud-native bioinformatics system by adding:

1. **Nextflow Execution**: Run workflows using Nextflow's powerful DSL2 engine with support for AWS Batch, Slurm, and local execution

2. **AI Operations**: LLM-powered intelligent log analysis, natural language queries, and automated insights

3. **AutoFix Framework**: Automatic detection and repair of workflow failures with risk-based approval and complete audit trails

4. **Workflow Interoperability**: Bi-directional conversion between Galaxy and Nextflow formats, enabling import of nf-core pipelines

5. **Cloud-Native Support**: S3 data management, CloudWatch integration, and cost optimization

6. **Enhanced Monitoring**: Real-time multi-source log analysis and intelligent alerting

These additions maintain full backward compatibility with standard Galaxy while providing a significantly enhanced platform for modern bioinformatics workflows.
