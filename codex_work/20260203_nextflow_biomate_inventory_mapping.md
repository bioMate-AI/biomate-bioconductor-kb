# Nextflow ↔ BioMate Inventory & Mapping

**Date**: 2026-02-03
**Status**: Backend Merge Phase 1 Complete

## Merge Progress

### Phase 1: Core Nextflow Execution (COMPLETED)
- ✅ Copied 9 Nextflow runner files to `backend/lib/galaxy/jobs/runners/`
- ✅ Copied 3 container resolver files
- ✅ Copied 10 workflow converter files to `backend/lib/galaxy/workflow/converters/`
- ✅ Copied Nextflow scheduler to `backend/lib/galaxy/workflow/schedulers/`
- ✅ Copied workflow_ops module (AutoFix + 20+ files) to `backend/lib/galaxy/ai/workflow_ops/`
- ✅ Copied 5 API endpoint files to `backend/lib/galaxy/webapps/galaxy/api/`
- ✅ Updated `galaxy.yml.template` with Nextflow executor configuration
- ✅ Workflow converters import correctly

### Phase 1 Completed ✅
- ✅ Installed all required components
- ✅ Fixed all import paths (absolute → relative)
- ✅ All 10 integration tests passing

### Phase 2: Frontend Routes (COMPLETED)
- ✅ Added `/api/workflows/runs/:id/ai/analyze` - AI workflow analysis
- ✅ Added `/api/workflows/runs/:id/ai/autofix` - Trigger AutoFix
- ✅ Added `/api/workflows/runs/:id/ai/query` - Natural language queries
- ✅ Added `/api/workflows/runs/:id/logs` - Real-time logs
- ✅ Added `/api/workflows/convert/galaxy-to-nextflow` - Convert workflow
- ✅ Added `/api/workflows/convert/nextflow-to-galaxy` - Convert workflow

### Optional Remaining Tasks
- ⏳ Install `pulsar-galaxy-lib` for full job runner functionality (optional)
- ⏳ Install `aiohttp` for async HTTP operations (optional, warning only)

## Executive Summary

This document maps components between `galaxy_nextflow` and `biomate` to guide the integration of Nextflow execution capabilities into BioMate.

### Galaxy Data Management Continuity (Soft Fallback)
- **Primary path**: Nextflow executions still write outputs into **Galaxy histories**, preserving uploads, dataset management, and interactive visualization.
- **Soft fallback**: If outputs are missing, re-resolve the **actual history ID** via Galaxy invocation and retry output fetch.
- **Avoid divergence**: Do not read directly from Nextflow work directories unless Galaxy sync is unavailable and explicitly required.

---

## 1. Component Inventory

### 1.1 Galaxy Nextflow Components (~55 modules)

#### Nextflow Execution (12 files)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `lib/galaxy/jobs/runners/nextflow_runner.py` | `NextflowJobRunner` | Executes Galaxy tools as Nextflow processes |
| `lib/galaxy/jobs/runners/nextflow_workflow_runner.py` | `NextflowWorkflowRunner` | Executes full Galaxy workflows as Nextflow pipelines |
| `lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/nextflow_executor.py` | `NextflowExecutor` | Cloud executor for AWS Batch with S3 I/O |
| `lib/galaxy/jobs/runners/nextflow_batch_log_collector.py` | `BatchLogCollector` | Collects AWS Batch logs from CloudWatch |
| `lib/galaxy/jobs/runners/nextflow_s3_manager.py` | - | S3 data transfer for Nextflow |
| `lib/galaxy/jobs/runners/nextflow_cloud_data_manager.py` | - | Cloud data management |
| `lib/galaxy/jobs/runners/biocontainer_resolver.py` | - | Resolves BioContainers |
| `lib/galaxy/jobs/runners/nextflow_tool_sync.py` | `NextflowToolSynchronizer` | Syncs Galaxy tools to S3 |
| `lib/galaxy/jobs/runners/smart_container_resolver.py` | - | Intelligent container resolution |
| `lib/galaxy/jobs/runners/unified_container_resolver.py` | - | Unified container strategy |
| `lib/galaxy/jobs/runners/nextflow_remote_executor.py` | - | Remote execution support |
| `lib/galaxy/jobs/runners/nextflow_workflow_converter.py` | `GalaxyToNextflowConverter` | Runtime converter for Galaxy→Nextflow |

#### AutoFix (20+ files)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `lib/galaxy/ai/workflow_ops/autofix/orchestrator.py` | `AutoFixOrchestrator` | Main orchestrator with permissions, budget, rollback |
| `lib/galaxy/ai/workflow_ops/autofix/workflow_restarter.py` | `WorkflowRestarter` | Restarts workflows after fixes |
| `lib/galaxy/ai/workflow_ops/autofix/fixers/nextflow_parameter_fixer.py` | - | Nextflow parameter fixes |
| `lib/galaxy/ai/workflow_ops/autofix/fixers/container_error_fixer.py` | - | Container error fixes |
| `lib/galaxy/ai/workflow_ops/autofix/fixers/reference_genome_fixer.py` | - | Reference genome path fixes |
| `lib/galaxy/ai/workflow_ops/autofix/fixers/aws_resource_fixer.py` | - | AWS resource fixes |
| `lib/galaxy/ai/workflow_ops/autofix/fixers/samplesheet_fixer.py` | - | Samplesheet format fixes |
| `lib/galaxy/ai/workflow_ops/autofix/fixers/file_format_fixer.py` | - | File format fixes |
| `lib/galaxy/ai/workflow_ops/autofix/fixers/retry_strategy_fixer.py` | - | Retry strategy implementation |
| `lib/galaxy/ai/workflow_ops/autofix/fixers/llm_first_fixer.py` | - | LLM-first error fixing |
| `lib/galaxy/ai/workflow_ops/autofix/parameter_mapper.py` | `UniversalParameterMapper` | Maps params to pipeline-specific |
| `lib/galaxy/ai/workflow_ops/autofix/llm_parameter_mapper.py` | `LLMParameterMapper` | LLM-driven parameter mapping |
| `lib/galaxy/ai/workflow_ops/autofix/validation.py` | `FixValidator`, `FixSimulator` | Validates and simulates fixes |
| `lib/galaxy/ai/workflow_ops/auto_healer.py` | `WorkflowAutoHealer` | Main auto-healing service |

#### Workflow Conversion (10 files)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `lib/galaxy/workflow/converters/galaxy_to_nextflow_converter.py` | `GalaxyToNextflowConverter` | Converts Galaxy .ga → Nextflow DSL2 |
| `lib/galaxy/workflow/converters/nextflow_to_galaxy_converter.py` | `NextflowToGalaxyConverter` | Converts Nextflow DSL2 → Galaxy .ga |
| `lib/galaxy/workflow/converters/nextflow_tool_generator.py` | `NextflowToolGenerator` | Generates Galaxy tool XML for NF processes |
| `lib/galaxy/workflow/converters/nextflow_schema_parser.py` | - | Parses Nextflow schema files |
| `lib/galaxy/workflow/converters/nextflow_pipeline_importer.py` | - | Imports Nextflow pipelines |
| `lib/galaxy/workflow/converters/universal_nextflow_param_extractor.py` | - | Universal parameter extraction |
| `lib/galaxy/workflow/converters/schema_to_galaxy_tool.py` | - | Schema → Galaxy tool definitions |
| `lib/galaxy/workflow/converters/igenomes_detector.py` | - | Detects iGenomes references |

#### Monitoring (8 files)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `lib/galaxy/jobs/runners/nextflow_monitor.py` | `NextflowMonitor`, `NextflowMonitorService` | Real-time log streaming, status polling |
| `lib/galaxy/ai/workflow_ops/log_analyzer.py` | `WorkflowLogAnalyzer` | LLM log analysis |
| `lib/galaxy/ai/workflow_ops/comprehensive_log_analyzer.py` | - | Detailed issue detection |
| `lib/galaxy/ai/workflow_ops/error_search_agent.py` | - | AI error search agent |
| `lib/galaxy/workflow/scheduling_manager.py` | - | Workflow scheduling |
| `lib/galaxy/workflow/schedulers/nextflow.py` | - | Nextflow-specific scheduler |

#### API Endpoints (5 files)
| File | Endpoints | Purpose |
|------|-----------|---------|
| `lib/galaxy/webapps/galaxy/api/workflow_ai_ops.py` | `/api/workflows/{id}/ai/analyze`, `/ai/autofix`, `/ai/query` | AI workflow operations |
| `lib/galaxy/webapps/galaxy/api/workflow_ai_realtime.py` | - | Real-time status streaming |
| `lib/galaxy/webapps/galaxy/api/workflow_converters.py` | - | Workflow conversion API |
| `lib/galaxy/webapps/galaxy/api/autofix3.py` | - | AutoFix 3.0 API |

---

### 1.2 BioMate Components

#### Workflow Generation (Backend)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `backend/lib/galaxy/ai/ai_assistant.py` | `AIAssistant` | Main orchestrator (search-first approach) |
| `backend/lib/galaxy/ai/galaxy_workflow_generator.py` | `GalaxyWorkflowGenerator` | Tool-constrained workflow generator |
| `backend/lib/galaxy/ai/enhanced_workflow_generator.py` | `EnhancedWorkflowGenerator` | Template/RAG-based generation |
| `backend/lib/galaxy/ai/workflow_generator.py` | `WorkflowGenerator` | Task-based workflow generation |
| `backend/lib/galaxy/ai/propose_validate_workflow_generator.py` | `ProposeValidateWorkflowGenerator` | LLM propose + validate |

#### Tool Search (Backend)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `backend/lib/galaxy/ai/unified_tool_search.py` | `UnifiedToolSearch` | Multi-stage retrieval (LLM + vector + FTS5) |
| `backend/lib/galaxy/ai/tool_recommender.py` | `ToolRecommender` | Tool recommendation for tasks |
| `backend/lib/galaxy/ai/vector_search.py` | `VectorToolSearch` | Semantic similarity search |
| `backend/lib/galaxy/ai/query_analyzer.py` | `LLMQueryAnalyzer` | Query analysis |

#### Workflow Search (Backend)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `backend/lib/galaxy/ai/unified_workflow_search.py` | `UnifiedWorkflowSearch` | Search 951+ workflows (nf-core, biomni, Galaxy) |
| `backend/lib/galaxy/ai/workflow_templates.py` | `WorkflowTemplateLibrary` | Template library |

#### Parameter Inference & Validation (Backend)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `backend/lib/galaxy/ai/llm_parameter_generator.py` | `LLMParameterGenerator` | LLM-based parameter inference |
| `backend/lib/galaxy/ai/workflow_proposal_validator.py` | `WorkflowProposalValidator` | Validate against tool index |
| `backend/lib/galaxy/ai/workflow_optimizer.py` | `WorkflowOptimizer` | Workflow optimization |

#### Execution (Frontend Server)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `frontend/server/galaxy-api-proxy.ts` | `GalaxyAPIProxy` | HTTP client for Galaxy API |
| `frontend/server/galaxy-state-poller.ts` | `GalaxyStatePoller` | Polls invocation status with exponential backoff |
| `frontend/server/workflow-sse.ts` | `WorkflowSSEManager` | SSE for real-time updates |
| `frontend/server/workflow-prerequisites-validator.ts` | `WorkflowPrerequisitesValidator` | Pre-execution validation |
| `frontend/server/galaxy-assistant.ts` | `GalaxyAssistant` | Frontend AI orchestrator |

#### Storage (Frontend)
| File | Class/Module | Purpose |
|------|--------------|---------|
| `frontend/server/storage.ts` | `MemStorage` | In-memory execution tracking |
| `frontend/shared/galaxy-types.ts` | Types | TypeScript types for execution |
| `frontend/shared/schema.ts` | Schema | Database schema (Drizzle ORM) |

#### API Routes (Frontend)
| File | Key Endpoints | Purpose |
|------|---------------|---------|
| `frontend/server/routes.ts` | `/api/chat`, `/api/workflows/execute`, `/api/workflows/runs/:id/status` | Main API |

---

## 2. Component Mapping

### 2.1 Execution Layer

| BioMate Component | Galaxy Nextflow Equivalent | Integration Strategy |
|-------------------|----------------------------|---------------------|
| `GalaxyAPIProxy.invokeWorkflow()` | `NextflowWorkflowRunner.queue_job()` | Extend `GalaxyAPIProxy` with Nextflow execution path |
| `GalaxyStatePoller.pollInvocation()` | `NextflowMonitor.monitor_once()` | Create `NextflowStatePoller` with same event contract |
| `WorkflowSSEManager` | N/A (direct polling) | Reuse SSE manager, add Nextflow event source |
| `MemStorage.createExecutionRun()` | N/A | Extend schema to track `executionEngine: 'galaxy' | 'nextflow'` |

### 2.2 Workflow Generation

| BioMate Component | Extension Needed |
|-------------------|------------------|
| `AIAssistant.generate_workflow_unified()` | Add `format: 'nextflow'` param, use Nextflow converters |
| `GalaxyWorkflowGenerator` | Add `generate_nextflow_workflow()` variant |
| `UnifiedWorkflowSearch` | Already supports `source: 'nfcore'` filter |

### 2.3 AutoFix Integration

| Galaxy Nextflow Component | BioMate Integration Point |
|---------------------------|---------------------------|
| `AutoFixOrchestrator` | New endpoint `/api/workflows/runs/:id/autofix` |
| `WorkflowRestarter` | Integrate with `GalaxyAPIProxy` for restart |
| Fixers (8 types) | Port all to `backend/lib/galaxy/ai/workflow_ops/autofix/` |

### 2.4 Monitoring & Logging

| Galaxy Nextflow Component | BioMate Integration Point |
|---------------------------|---------------------------|
| `NextflowMonitorService` | Background service in backend |
| `BatchLogCollector` | Add CloudWatch log retrieval |
| `WorkflowLogAnalyzer` | Integrate with existing LLM infrastructure |

---

## 3. Shared Module Opportunities

### 3.1 Validation Logic Overlap

Both systems have validation logic that can be unified:

**BioMate Validation:**
- `WorkflowPrerequisitesValidator` - Pre-execution validation
- `WorkflowProposalValidator` - Workflow proposal validation
- `ToolIndexValidator` - Tool existence validation

**Galaxy Nextflow Validation:**
- `FixValidator` - Fix validation
- `FixSimulator` - Outcome simulation
- Parameter validation in fixers

**Shared Module Proposal:**
```
backend/lib/galaxy/workflow/shared_validation/
├── __init__.py
├── tool_validator.py        # Tool existence/compatibility
├── parameter_validator.py   # Parameter schema validation
├── input_validator.py       # Input dataset compatibility
├── execution_readiness.py   # Pre-execution checks
└── interfaces.py            # Common interfaces
```

### 3.2 Parameter Mapping Overlap

**BioMate:**
- `LLMParameterGenerator` - Generates params from intent

**Galaxy Nextflow:**
- `UniversalParameterMapper` - Maps AutoFix params
- `LLMParameterMapper` - LLM-driven mapping

**Shared Module Proposal:**
```
backend/lib/galaxy/ai/parameter_mapping/
├── __init__.py
├── llm_mapper.py           # LLM-based mapping (shared)
├── schema_mapper.py        # Schema-driven mapping
└── pipeline_adapters/      # Pipeline-specific adapters
    ├── nfcore.py
    └── galaxy.py
```

---

## 4. Integration Priority

### Phase 1: Core Execution (Current Focus)
1. ✅ Inventory complete
2. 🔄 Port `NextflowWorkflowRunner` → `backend/lib/galaxy/jobs/runners/`
3. Port `NextflowMonitor` → enable status polling
4. Port converters → `backend/lib/galaxy/workflow/converters/`

### Phase 2: AutoFix
1. Port `AutoFixOrchestrator` and all fixers
2. Expose `/api/workflows/{id}/ai/autofix` endpoint
3. Integrate with frontend UI

### Phase 3: Frontend Integration
1. Extend `GalaxyStatePoller` for Nextflow
2. Add execution mode selection to UI
3. Display Nextflow-specific status/logs

### Phase 4: Shared Modules
1. Extract shared validation interfaces
2. Create unified parameter mapping
3. Refactor both systems to use shared modules

---

## 5. Key Files to Port

### Immediate (Phase 1)
```
galaxy_nextflow → biomate/backend

lib/galaxy/jobs/runners/nextflow_workflow_runner.py
lib/galaxy/jobs/runners/nextflow_monitor.py
lib/galaxy/jobs/runners/nextflow_s3_manager.py
lib/galaxy/workflow/converters/galaxy_to_nextflow_converter.py
lib/galaxy/workflow/schedulers/nextflow.py
```

### Phase 2
```
lib/galaxy/ai/workflow_ops/autofix/orchestrator.py
lib/galaxy/ai/workflow_ops/autofix/workflow_restarter.py
lib/galaxy/ai/workflow_ops/autofix/fixers/*.py
lib/galaxy/ai/workflow_ops/auto_healer.py
lib/galaxy/ai/workflow_ops/log_analyzer.py
lib/galaxy/webapps/galaxy/api/workflow_ai_ops.py
```

---

## 6. API Endpoint Mapping

### New Endpoints to Add in BioMate

| Endpoint | Method | Purpose | Source |
|----------|--------|---------|--------|
| `/api/workflows/execute/nextflow` | POST | Execute as Nextflow | New |
| `/api/workflows/runs/:id/logs` | GET | Stream Nextflow logs | `workflow_ai_realtime.py` |
| `/api/workflows/runs/:id/autofix` | POST | Trigger AutoFix | `workflow_ai_ops.py` |
| `/api/workflows/runs/:id/autofix/status` | GET | AutoFix status | `workflow_ai_ops.py` |
| `/api/workflows/convert/galaxy-to-nextflow` | POST | Convert workflow | `workflow_converters.py` |
| `/api/workflows/convert/nextflow-to-galaxy` | POST | Convert workflow | `workflow_converters.py` |

---

## Appendix: File Counts

| Category | Galaxy Nextflow | BioMate | Total After Merge |
|----------|-----------------|---------|-------------------|
| Execution | 12 | 5 | ~15 (merge runners) |
| AutoFix | 20+ | 0 | 20+ (port all) |
| Conversion | 10 | 0 | 10 (port all) |
| Monitoring | 8 | 3 | ~8 (merge pollers) |
| API | 5 | 1 | ~6 (add Nextflow APIs) |
| **Total** | **55+** | **~20** | **~60** |
