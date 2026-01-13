# BioMate Agent Hierarchy Architecture

## Overview

BioMate already implements a sophisticated 3-layer agent hierarchy for bioinformatics workflow generation. This document details the existing implementation and compares it with iFlow to identify genuine enhancement opportunities.

## Existing Agent Architecture

### Layer 1: Intent Classification (UnifiedIntentRouter)

**Location**: `backend/lib/galaxy/ai/agents/unified_intent_router.py`

Routes user queries to appropriate handlers based on intent type:

| Intent Type | Handler | Description |
|-------------|---------|-------------|
| `workflow_generation` | AgentOrchestrator | Create/run analysis pipelines |
| `research_question` | ResearchAgent | Scientific questions |
| `result_comparison` | ResearchAgent + Benchmark | Compare tools/methods |
| `tool_search` | UnifiedToolSearch | Find available tools |
| `tool_recommendation` | ResearchAgent + Benchmark | Recommend best tool |
| `benchmark_query` | BenchmarkKnowledgeDB | Performance data |
| `conclusion_drawing` | ResearchAgent | Interpret results |
| `literature_survey` | ResearchAgent | Literature search |
| `parameter_help` | ToolSearch | Parameter documentation |
| `general_question` | ResearchAgent | Catch-all |

**Classification Method**: Hybrid keyword matching + LLM fallback
- Keyword patterns for each intent (fast, <10ms)
- LLM fallback when confidence < 0.6
- Entity extraction: tools, analysis types, organisms, data types

### Layer 2: Agent Orchestration (AgentOrchestrator)

**Location**: `backend/lib/galaxy/ai/agents/agent_orchestrator.py`

Coordinates the 3-agent workflow generation pipeline:

```
User Query
    │
    ▼
┌─────────────────────────────────────┐
│  Phase 1: EnhancedDomainRouter      │
│  (Hybrid Keyword + LLM Routing)     │
│  Output: Primary + Secondary Domains │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  Phase 2: DomainSpecialistPool      │
│  (Parallel Domain Experts)          │
│  Output: Per-domain Recommendations  │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│  Phase 3: WorkflowAssembler         │
│  (Synthesis + Validation)           │
│  Output: Unified Galaxy Workflow    │
└─────────────────────────────────────┘
```

**Key Features**:
- **Configurable parallel execution**: `max_parallel_specialists=3`
- **User context integration**: Via UserPatternsAdapter
- **Audit logging**: Per-phase timing and results
- **Learning integration**: Corrections fed back

### Layer 3: Domain Specialists

#### 3a. EnhancedDomainRouter

**Location**: `backend/lib/galaxy/ai/agents/enhanced_domain_router.py`

**15 Bioinformatics Domains**:

| Domain | Key Keywords |
|--------|-------------|
| genomics | genome, dna, sequencing, variant calling, snp |
| transcriptomics | rna-seq, gene expression, deseq2, differential expression |
| proteomics | protein, mass spec, dia, dda, peptide |
| metabolomics | metabolite, lcms, gcms, metabolome |
| single-cell | scrna-seq, scatac, single cell, 10x |
| metagenomics | microbiome, 16s, shotgun, kraken |
| structural_biology | pdb, alphafold, docking, molecular dynamics |
| pharmacology | drug, compound, admet, docking |
| immunology | immune, tcr, bcr, epitope |
| cancer_biology | tumor, oncology, somatic, mutation |
| bioimaging | microscopy, image, segmentation, fluorescence |
| molecular_biology | pcr, cloning, primer, plasmid |
| biochemistry | enzyme, kinetics, assay, binding |
| database | query, search, fetch, retrieve |
| literature | papers, pubmed, citations, review |

**Routing Algorithm**:
```python
def route(query, user_id, user_context):
    # Step 1: Keyword scoring (fast)
    keyword_result = _keyword_route(query)

    # Step 2: Apply user preference boost
    if user_context and user_context.domain_preference:
        keyword_result = _apply_user_boost(keyword_result, user_context)

    # Step 3: LLM fallback if low confidence
    if keyword_result.confidence < LLM_THRESHOLD (0.7):
        return _llm_route(query, keyword_result, user_context)

    return keyword_result
```

**Caching**: LRU cache for LLM decisions (max 1000 entries, TTL 3600s)

#### 3b. DomainSpecialistPool

**Location**: `backend/lib/galaxy/ai/agents/domain_specialist.py`

**Parallel Execution**:
```python
with ThreadPoolExecutor(max_workers=min(len(domains), self.max_workers)) as executor:
    futures = {
        executor.submit(self._consult_single, query, domain, tools_per_domain): domain
        for domain in domains
    }
```

**Domain-Specific Prompts**: Each domain has a tailored system prompt:
- "You are a genomics expert specializing in DNA analysis..."
- "You are a transcriptomics expert specializing in RNA-seq..."
- etc.

**Tool Filtering**: Each specialist only sees tools relevant to their domain (`tools_per_domain=15`)

#### 3c. WorkflowAssembler

**Location**: `backend/lib/galaxy/ai/agents/workflow_assembler.py`

**Responsibilities**:
1. **Merge**: Combine recommendations from multiple domain specialists
2. **Validate**: Check tool compatibility and data flow
3. **Synthesize**: Generate Galaxy workflow JSON
4. **Cite**: Add benchmark citations where applicable

### Supporting Components

#### UserPatternsAdapter

**Location**: `backend/lib/galaxy/ai/agents/user_patterns_adapter.py`

**Bridges user learning to multi-agent system**:

| Data Type | Purpose | Storage |
|-----------|---------|---------|
| Domain Preferences | Boost routing for preferred domains | SQLite |
| Tool Preferences | Prioritize frequently used tools | SQLite |
| Learned Keywords | User-specific domain indicators | SQLite |
| Expertise Level | Adjust explanation detail | SQLite |
| Recent Domains | Context for ambiguous queries | In-memory |

**Learning Loop**:
```
User Correction → UserPatternsAdapter.update_* → SQLite
                                                    ↓
Next Query ← EnhancedDomainRouter ← get_routing_context()
```

---

## Comparison: BioMate vs iFlow

### What BioMate Already Has

| Feature | BioMate Implementation | iFlow Equivalent |
|---------|------------------------|------------------|
| **Intent Classification** | UnifiedIntentRouter (10 types) | Task routing |
| **Domain Routing** | EnhancedDomainRouter (15 domains) | Agent selection |
| **Parallel Execution** | ThreadPoolExecutor (3 workers) | asyncio tasks |
| **Specialized Agents** | DomainSpecialistPool | Domain agents |
| **Workflow Synthesis** | WorkflowAssembler | Workflow composition |
| **User Learning** | UserPatternsAdapter | Memory system |
| **Hybrid Routing** | Keyword + LLM | Similar hybrid |
| **Caching** | LRU cache for LLM decisions | Response caching |
| **Audit Trail** | Per-phase logging | Task logging |

### Genuine Gaps (What iFlow Has That BioMate Lacks)

#### 1. Standardized Message Protocol

**iFlow**: Agent Communication Protocol (ACP) with typed messages:
- `AssistantMessage` - Text responses
- `ToolCallMessage` - Tool invocations
- `PlanMessage` - Multi-step planning
- `TaskFinishMessage` - Completion status

**BioMate Gap**: No standardized message format between agents. Currently uses ad-hoc dictionaries.

**Proposed Enhancement**:
```python
@dataclass
class AgentMessage:
    message_type: MessageType  # PLAN, TOOL_CALL, RESULT, ERROR
    sender: str  # domain_router, genomics_specialist, etc.
    content: Dict[str, Any]
    timestamp: float
    trace_id: str  # For distributed tracing
```

#### 2. Checkpointing / State Persistence

**iFlow**: Can suspend and resume agent tasks with full state preservation.

**BioMate Gap**: No checkpoint mechanism. If orchestration fails mid-way, must restart.

**IMPORTANT - Galaxy Does NOT Have True Checkpointing**:

Galaxy provides state TRACKING, not checkpoint/resume:

| Galaxy Feature | What It Does | Why It's NOT Checkpointing |
|----------------|--------------|----------------------------|
| `InvocationState` | Track: NEW → READY → SCHEDULED → FAILED | No state persistence for recovery |
| Job `RESUBMITTED` | Mark manually re-run jobs | Manual action, not auto resume |
| Step-level tracking | Each step: NEW/READY/SCHEDULED | Tracks progress, doesn't save it |
| `cancel_invocation()` | Stop running workflow | No "resume" API exists |

**Galaxy's limitation**: If workflow fails at step 15 of 20, must restart from step 1.

---

**NEXTFLOW HAS BUILT-IN CHECKPOINT/RESUME** (Future Execution Engine):

When BioMate switches to Nextflow, workflow checkpoint/resume is solved:

| Nextflow Feature | How It Works |
|------------------|--------------|
| **`-resume` flag** | `nextflow run pipeline.nf -resume` skips completed tasks |
| **Automatic caching** | Every task cached in `.nextflow/cache` (LevelDB) |
| **Hash-based validation** | Re-runs only if inputs/scripts/containers change |

**Example**: `nextflow run rnaseq.nf -resume` - skips steps 1-14, continues from 15.

**What still needs custom checkpointing** (even with Nextflow):

| Component | Needs Checkpoint? | Why |
|-----------|-------------------|-----|
| Workflow Execution | **NO** | Nextflow handles it |
| Agent Orchestration | **YES** | Conversation context, routing |
| Test Harness | **YES** | Benchmarks don't use Nextflow |

---

**Proposed Enhancement for Agent Orchestration** (still needed):
```python
class CheckpointManager:
    def save_checkpoint(self, session_id: str, state: OrchestrationState):
        """Save orchestration state to Redis/SQLite"""

    def restore_checkpoint(self, session_id: str) -> Optional[OrchestrationState]:
        """Restore from last checkpoint"""
```

**Also needed for Test Harness** (`benchmark_suite.py`):
- Currently no checkpoint - 100 benchmark runs fail at run 50 = all progress lost
- Add `save_checkpoint()` after each successful run
- Add `resume_from_checkpoint()` to skip completed runs

#### 3. Sub-Agent Spawning with Permission Inheritance

**iFlow**: Parent agents can spawn sub-agents that inherit tool permissions.

**BioMate Gap**: Specialists are pre-defined, not dynamically spawned.

**Proposed Enhancement** (if needed):
```python
class DynamicSpecialist:
    def spawn_sub_specialist(self, task: str, parent_tools: List[str]) -> Specialist:
        """Spawn a focused sub-agent for a specific sub-task"""
```

#### 4. Structured Planning Stage

**iFlow**: Explicit plan generation and approval before execution.

**BioMate Gap**: Domain routing happens implicitly. User doesn't see the routing decision.

**Proposed Enhancement**:
```python
class PlanningStage:
    def generate_plan(self, query: str) -> WorkflowPlan:
        """Generate explicit plan for user approval"""
        return WorkflowPlan(
            domains=["transcriptomics", "genomics"],
            specialists_to_consult=["rna_seq_expert", "variant_caller_expert"],
            estimated_tools=["salmon", "star", "gatk"],
            rationale="Query involves both expression and variant analysis..."
        )
```

#### 5. Tool Permission Scoping

**iFlow**: Strict tool permissions per agent type.
```yaml
agentType: "genomics-analyst"
allowedTools: ["bwa", "gatk", "deepvariant", "samtools"]  # WHITELIST - agent CANNOT use other tools
```

**BioMate Gap - Current "Soft Filtering"**:

In `domain_specialist.py`:
```python
def consult_specialists(self, query, domains, tools_per_domain=15):  # <-- SOFT FILTER
```

**How it currently works**:
1. Genomics specialist REQUESTS genomics-related tools
2. Tool search returns 15 filtered tools
3. LLM sees those 15 tools in its prompt
4. **BUT**: Nothing PREVENTS the LLM from recommending ANY tool it knows about

**Problem scenarios**:
- LLM might hallucinate tool names that don't exist
- Cross-domain recommendations (proteomics tool for genomics data)
- Inconsistent tool suggestions across sessions

**Proposed Enhancement - Strict Validation**:
```python
DOMAIN_TOOL_PERMISSIONS = {
    "genomics": {"bwa", "bwa-mem2", "gatk", "deepvariant", "samtools", "bcftools", "freebayes"},
    "transcriptomics": {"star", "salmon", "kallisto", "deseq2", "edger", "htseq", "rsem"},
    "proteomics": {"maxquant", "dia-nn", "msfragger", "percolator", "comet"},
    "single-cell": {"scanpy", "seurat", "cellranger", "scvi", "harmony"},
    "structural_biology": {"alphafold", "colabfold", "autodock-vina", "pymol"},
    # ... strict boundaries per domain
}

def validate_tool_recommendation(self, domain: str, tool_id: str) -> Tuple[bool, str]:
    """Validate recommended tool is within domain's permission scope."""
    allowed = DOMAIN_TOOL_PERMISSIONS.get(domain, set())
    tool_lower = tool_id.lower()

    if tool_lower in allowed:
        return True, f"Tool {tool_id} approved for {domain}"

    # Check partial matches (e.g., "gatk_haplotypecaller" matches "gatk")
    for approved in allowed:
        if tool_lower.startswith(approved) or approved in tool_lower:
            return True, f"Tool {tool_id} matches pattern {approved}"

    return False, f"Tool {tool_id} not in {domain} approved list"
```

**Benefits of strict enforcement**:
- Guaranteed tool validity (no hallucinated tools)
- Domain-appropriate recommendations
- Consistent, predictable behavior
- Easier to audit and debug

---

## Recommended Enhancements

Based on the gap analysis, prioritized enhancements:

### Priority 1: Standardized Message Protocol (BCP)

**Rationale**: Enables better debugging, distributed tracing, and audit logging.

**Implementation Effort**: Low
**Impact**: Medium (debugging, observability)

### Priority 2: Checkpoint/Resume Capability

**Rationale**: Long-running workflows should survive failures.

**Implementation Effort**: Medium
**Impact**: High (reliability)

### Priority 3: Explicit Planning Stage

**Rationale**: User transparency and approval before expensive LLM calls.

**Implementation Effort**: Medium
**Impact**: High (user trust, cost control)

### Priority 4: Tool Permission Enforcement

**Rationale**: Prevents cross-domain tool hallucination.

**Implementation Effort**: Low
**Impact**: Medium (accuracy)

### Not Recommended

- **Dynamic Sub-Agent Spawning**: BioMate's pre-defined domain specialists are sufficient for bioinformatics use cases. Dynamic spawning adds complexity without clear benefit.

---

## Architecture Summary Diagram

```
                            ┌───────────────────────────┐
                            │   User Query Input        │
                            └───────────┬───────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 1: Intent Classification (UnifiedIntentRouter)                       │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ 10 Intent Types: workflow_generation, research_question, ...        │    │
│  │ Keyword Matching (<10ms) + LLM Fallback (confidence < 0.6)          │    │
│  │ Entity Extraction: tools, organisms, data types                     │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
          ┌─────────────────────┼─────────────────────┐
          │                     │                     │
          ▼                     ▼                     ▼
    ┌───────────┐       ┌───────────────┐     ┌──────────────┐
    │ Workflow  │       │   Research    │     │  Tool Search │
    │ Generation│       │    Agent      │     │              │
    └─────┬─────┘       └───────────────┘     └──────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 2: Agent Orchestration (AgentOrchestrator)                           │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ Phase 1: EnhancedDomainRouter (Hybrid Keyword + LLM)                │    │
│  │   - 15 bioinformatics domains                                       │    │
│  │   - LRU cache for LLM decisions                                     │    │
│  │   - User preference boost                                           │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                │                                            │
│                                ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ Phase 2: DomainSpecialistPool (Parallel Domain Experts)             │    │
│  │   - ThreadPoolExecutor (max_workers=3)                              │    │
│  │   - Domain-specific system prompts                                  │    │
│  │   - Tool filtering per domain (max 15 tools)                        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                │                                            │
│                                ▼                                            │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ Phase 3: WorkflowAssembler (Synthesis + Validation)                 │    │
│  │   - Merge multi-domain recommendations                              │    │
│  │   - Validate tool compatibility                                     │    │
│  │   - Generate Galaxy workflow JSON                                   │    │
│  │   - Add benchmark citations                                         │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  LAYER 3: Supporting Components                                             │
│  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────────┐    │
│  │ UserPatterns      │  │ BenchmarkKnowledge │  │ AuditService          │    │
│  │ Adapter           │  │ DB                 │  │                       │    │
│  │                   │  │                    │  │                       │    │
│  │ - Domain prefs    │  │ - Tool benchmarks  │  │ - Per-phase timing    │    │
│  │ - Tool prefs      │  │ - Citations        │  │ - Request logging     │    │
│  │ - Learned keywords│  │ - Performance data │  │ - Error tracking      │    │
│  └───────────────────┘  └───────────────────┘  └───────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Conclusion

BioMate already has a mature agent hierarchy that covers most of iFlow's architectural patterns. The genuine gaps are:

1. **Message Protocol**: Standardize inter-agent communication
2. **Checkpointing**: Enable suspend/resume for reliability
3. **Planning Stage**: Make routing decisions transparent to users
4. **Permission Enforcement**: Strict tool boundaries per domain

These enhancements would improve reliability, observability, and user trust without requiring a fundamental architecture change.
