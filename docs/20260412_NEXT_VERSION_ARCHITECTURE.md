# BioMate Next Major Version — Architecture Analysis
# Date: 2026-04-12

---

## 1. Claude Code Open-Source Reference — Unexploited Leverage

The reference at `/home/yzhang/biomate/reference/claude-code/` contains a complete, production-grade plugin framework. Current BioMate integration is minimal. Below is a structured audit of what exists and what BioMate has not yet used.

### 1.1 Plugin Architecture (14 Official Plugins)

BioMate currently uses Claude Code as a development tool. It does **not** ship Claude Code plugins as part of its own product surface. The following patterns are directly applicable:

| Plugin | What it does | BioMate opportunity |
|--------|-------------|---------------------|
| `feature-dev` | 7-phase guided feature development with specialized subagents | BioMate could adopt this internally for dev velocity; also model for the bioinformatics workflow-design loop |
| `hookify` | Generates custom hooks from conversation patterns | BioMate's development process could be hookified: auto-validate that E2E tests pass before commits, auto-screenshot on Stop |
| `pr-review-toolkit` | 6 parallel specialized agents for code review | Could be adapted as BioMate's internal PR gate |
| `security-guidance` | Pre-edit security warnings | BioMate edits bioinformatics configs that can have security implications (S3 paths, credentials) — worth adding |
| `explanatory-output-style` / `learning-output-style` | Hook-based output transformation | Template for BioMate's "scientist mode" vs "operator mode" response styles |

### 1.2 Hook System — 8 Event Types, Currently Unused

Claude Code hooks fire on well-defined events. BioMate has hooks wired (`CLAUDE.md` dev loop) but has not built any automated hooks into the Claude Code sessions themselves.

**Immediately actionable hooks for BioMate's dev process:**

```
PreToolUse   → before any Edit/Write: check if file is in webpage_design/ (live site protection)
PreToolUse   → before Bash: warn if command touches production S3 bucket
PostToolUse  → after Write to e2e/*.ts: auto-run the affected test file
Stop         → enforce the CLAUDE.md iterative loop: require screenshot audit before marking done
SessionStart → load docs/0412_to_do.md automatically into context
```

**How to implement** (using `hookify` pattern from reference):
```json
// .claude/settings.local.json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{"type": "command", "command": "python3 .claude/hooks/live_site_guard.py"}]
    }],
    "Stop": [{
      "hooks": [{"type": "prompt", "prompt": "Has the full CLAUDE.md iterative loop completed? Require: test run green + screenshot reviewed."}]
    }]
  }
}
```

### 1.3 Skills System — Progressive Disclosure

The Skills architecture enables "lazy loading" of domain knowledge — only the skill relevant to the user's request gets loaded. This is exactly how BioMate's bioinformatics domain routing works conceptually, but it's implemented as Python code, not as a composable skill system.

**The deer-flow reference at `/home/yzhang/biomate/reference/deer-flow/skills/`** demonstrates 40+ skills. BioMate does not have a bioinformatics skills library, but could build one:

```
biomate-skills/
├── wgs-analysis/SKILL.md          # triggers: "analyze WGS", "germline variant calling"
├── drug-discovery/SKILL.md        # triggers: "ADMET", "docking", "MD simulation"
├── cryo-em/SKILL.md               # triggers: "cryo-EM", "particle picking", "3D reconstruction"
├── multi-omics/SKILL.md           # triggers: "RNA-seq", "ATAC-seq", "ChIP-seq integration"
├── report-generation/SKILL.md     # triggers: "generate report", "methods section"
└── parameter-explanation/SKILL.md # triggers: "what does X mean", "explain parameter"
```

Each SKILL.md carries its own system prompt fragment, reference docs, and example queries — no monolithic system prompt needed.

### 1.4 Agent Specialization Pattern

The `pr-review-toolkit` deploys 6 specialized parallel agents (security, performance, correctness, style, docs, tests) against a single PR. BioMate's current AI assistant is a single agent handling all roles. The reference pattern maps directly to BioMate's workflow validation problem:

**Proposed BioMate specialist agents** (modeled on `pr-review-toolkit`):
- `parameter-validator` — checks that params are biologically plausible
- `workflow-router` — pure routing, no conversation
- `report-writer` — consumes output files, writes publishable methods section
- `error-analyst` — analyzes failed run logs, proposes fix
- `prereq-resolver` — SRA / reference genome / accession lookup only

These can run in parallel using the existing Claude Code `Agent` tool pattern.

### 1.5 MCP Server Integration

The reference contains full MCP integration patterns (stdio, SSE, HTTP). BioMate currently has no MCP servers wired. The immediate opportunities:

| MCP server | What it enables |
|------------|-----------------|
| NCBI/SRA MCP | Auto-resolve accession IDs to metadata, genome builds, read counts |
| UniProt MCP | Protein function lookup during drug discovery parameter filling |
| PubMed MCP | Inject literature context into report generation |
| BioMate internal MCP | Expose workflow catalog, run history, QC profiles as tools to any Claude Code session |

The last one (BioMate as MCP server) is architecturally significant — it would let external tools (Cursor, Claude Desktop, other agents) call BioMate workflows programmatically.

---

## 2. Claude Managed Agents vs LangChain Deep Agents

### 2.1 What Claude Managed Agents Is

Anthropic's managed cloud infrastructure for running Claude-based agents. Key primitives:

- **Agent**: versioned resource — model + system prompt + tools + MCP servers
- **Environment**: cloud container with pre-installed packages, network access
- **Session**: running instance; persistent file system; steerable mid-run
- **Events**: SSE stream in/out

Beta endpoint: `POST /v1/sessions` with header `anthropic-beta: managed-agents-2026-04-01`

Built-in tools: bash, file ops, web search/fetch, MCP server calls.
Memory: persistent within a session's container filesystem.
Multi-agent: `callable_agents` field (research preview; one level of delegation).

### 2.2 What LangChain Deep Agents Is

Open-source agent harness on LangGraph runtime. Key API:

```python
from deepagents import create_deep_agent

agent = create_deep_agent(
    model="anthropic:claude-sonnet-4-6",   # provider-agnostic
    tools=[my_tool_fn],
    system_prompt="...",
)
agent.invoke({"messages": [...]})
```

12 capabilities: planning, context management, shell execution, subagent spawning, long-term memory (LangGraph Memory Store), filesystem permissions, human-in-the-loop, skills, pluggable backends (Modal, Daytona, Deno), LangSmith observability.

### 2.3 Comparison

| Dimension | Claude Managed Agents | LangChain Deep Agents |
|-----------|----------------------|----------------------|
| Infrastructure | Anthropic cloud containers | Pluggable (Modal, Daytona, in-memory, disk) |
| Model lock | Claude only | Any tool-calling model (OpenAI, Anthropic, Gemini) |
| Execution model | Event-driven SSE sessions | LangGraph durable execution |
| State | Session-scoped container FS | LangGraph Memory Store (persistent across sessions) |
| Multi-agent | `callable_agents` (1 level, research preview) | `task` tool → full subagent tree |
| Observability | Anthropic dashboard | LangSmith (rich tracing) |
| Cost model | Anthropic bills for compute + tokens | Your infra + model tokens |
| BioMate infra conflict | **High** — managed containers vs AWS Batch | **Low** — backends are pluggable |
| Open source | No | Yes (Apache 2.0) |

### 2.4 Conflict Analysis: Claude Managed Agents vs BioMate

BioMate's execution model is:
1. User query → AI assistant (runs on Galaxy backend, EC2)
2. Workflow matched → Nextflow launched on **AWS Batch** (containerized, GPU-capable)
3. Output files → S3 → rendered in frontend

Claude Managed Agents creates **its own** cloud containers and manages the execution environment. This creates direct conflict at multiple layers:

- **Container management**: Anthropic manages the container; BioMate already manages Batch compute environments (CPU + GPU queues, ECR images, AMI with AWS CLI)
- **Long-running jobs**: Nextflow workflows run 15 minutes to 2+ hours. Claude Managed Agents sessions are not designed for this; they're designed for coding/research tasks
- **GPU access**: BioMate requires GPU Batch jobs for MD simulation, cryo-EM. Anthropic's managed containers do not expose GPU accelerators
- **S3 integration**: BioMate's entire I/O model is S3. Managed Agent containers have a local FS, not S3 mounts
- **Existing infrastructure investment**: 63 Nextflow workflows, custom ECR images, GPU AMI, Lago billing integration — none portable to Anthropic-managed containers

**Verdict: Claude Managed Agents is architecturally incompatible with BioMate's current and planned execution model.** It would require abandoning AWS Batch and rebuilding the execution layer inside Anthropic's cloud — which removes GPU control, increases vendor lock-in, and discards a year of infrastructure work.

**Where it could be used within BioMate:** The AI assistant layer (the part that understands the query, matches the workflow, and fills parameters) is stateless and cloud-agnostic. A future version could run this layer as a Claude Managed Agent session — but this is incremental, not transformative.

### 2.5 LangChain Deep Agents Fit Analysis

Deep Agents' pluggable backend model aligns directly with BioMate's architecture:

| BioMate component | Deep Agents mapping |
|-------------------|---------------------|
| AI assistant (galaxy-assistant.ts) | `create_deep_agent(model="claude-sonnet-4-6", tools=[...])` |
| Workflow routing | tool function: `match_workflow(query) → WorkflowMatch` |
| AWS Batch execution | tool function: `submit_batch_job(workflow, params) → run_id` |
| S3 output polling | tool function: `poll_run_status(run_id) → status` |
| Parameter filling | tool function: `fill_params(workflow_schema, context) → params` |
| Cross-session memory | LangGraph Memory Store (replaces SQLite SessionMemory) |
| Subagent delegation | `task` tool → specialist agents (parameter-validator, report-writer, etc.) |
| Observability | LangSmith traces — every tool call, token count, latency visible |

**Verdict: LangChain Deep Agents is a strong architectural fit for BioMate v2.** The migration path is incremental: replace `galaxy-assistant.ts` with a Deep Agent, keep AWS Batch execution layer unchanged, gain LangSmith observability and durable multi-agent orchestration.

---

## 3. Architectural Proposal: BioMate v2

### 3.1 Core Principle

**Keep the execution layer. Replace the orchestration layer.**

BioMate's value is its bioinformatics execution infrastructure (Nextflow workflows, ECR images, AWS Batch, S3). The AI orchestration (intent routing, parameter filling, memory, report generation) is the layer that benefits from architectural upgrade.

### 3.2 Proposed Stack

```
┌─────────────────────────────────────────────────────────────┐
│  Frontend (React + Playwright E2E)        [unchanged]        │
├─────────────────────────────────────────────────────────────┤
│  API Layer (FastAPI routes.ts)            [thin pass-through]│
├─────────────────────────────────────────────────────────────┤
│  Deep Agent Orchestrator (LangGraph)      [NEW]              │
│  ┌──────────────┐  ┌────────────────┐  ┌────────────────┐  │
│  │ Router Agent │  │ Param Agent    │  │ Report Agent   │  │
│  │ (workflow    │  │ (parameter     │  │ (findings +    │  │
│  │  matching)   │  │  fill + valid) │  │  methods gen)  │  │
│  └──────────────┘  └────────────────┘  └────────────────┘  │
│  ┌──────────────┐  ┌────────────────┐                       │
│  │ Error Agent  │  │ Memory Store   │                       │
│  │ (run failure │  │ (LangGraph     │                       │
│  │  analysis)   │  │  persistent)   │                       │
│  └──────────────┘  └────────────────┘                       │
├─────────────────────────────────────────────────────────────┤
│  Tool Layer                               [unchanged/extended]│
│  ├── match_workflow() → unified_workflow_search.py          │
│  ├── submit_batch_job() → nextflow_executor.py              │
│  ├── poll_run_status() → nextflow_executor.py               │
│  ├── fill_params() → ai_assistant._apply_parameter_hints()  │
│  ├── ncbi_lookup() → [NEW MCP server]                       │
│  └── uniprot_lookup() → [NEW MCP server]                    │
├─────────────────────────────────────────────────────────────┤
│  Execution Layer (AWS Batch + Nextflow)   [unchanged]        │
│  ECR images, GPU queues, S3 I/O          [unchanged]        │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Migration Path (Incremental, Not Big Bang)

**Phase 1 — Observability (0 risk, immediate value)**
- Add LangSmith tracing to existing `galaxy-assistant.ts` Python calls
- Instrument every `search_nextflow_workflow` call, every LLM prompt
- Baseline: see where tokens/latency are actually going

**Phase 2 — Specialist Agents (additive, not replacing)**
- Extract `report-writer` as first Deep Agent subagent
- Triggered when run reaches `completed` status
- Runs in parallel to main conversation thread
- Produces methods section + structured findings JSON → feeds existing viewer

**Phase 3 — Memory Store Migration**
- Replace SQLite `SessionMemory` with LangGraph Memory Store
- Cross-session context (user's domain, past workflow preferences, common params)
- Enables: "use the same receptor file as last time" without manual re-upload

**Phase 4 — Full Orchestrator Migration**
- Replace `galaxy-assistant.ts` Python backbone with `create_deep_agent()`
- Tool functions wrap existing Python code unchanged
- LangGraph handles multi-turn state, context management, subagent coordination

**Phase 5 — MCP Server Layer**
- Build `biomate-mcp-server`: exposes catalog, run history, QC profiles as MCP tools
- External integrations: NCBI/SRA, UniProt, PubMed as stdlib MCP tools
- Enables: Claude Desktop, Cursor, and other agents to call BioMate workflows

### 3.4 Skills Library (Claude Code Plugin Format)

Build BioMate as a Claude Code plugin that ships bioinformatics skills. This is distinct from the backend architecture — it makes BioMate's domain expertise available inside Claude Code sessions used by bioinformaticians:

```
biomate-claude-plugin/
├── .claude-plugin/plugin.json
├── skills/
│   ├── wgs-analysis/SKILL.md
│   ├── drug-discovery/SKILL.md
│   ├── cryo-em/SKILL.md
│   ├── gromacs-md/SKILL.md
│   └── report-generation/SKILL.md
├── commands/
│   ├── biomate-run.md            # /biomate-run <query>
│   └── biomate-report.md         # /biomate-report <run_id>
└── .mcp.json                     # points to BioMate MCP server
```

This would be the first domain-specific Claude Code plugin in the bioinformatics space — a genuine moat.

---

## 4. Recommendations Summary

### Immediate (this sprint)
1. **Add `hookify` hooks** to dev process: protect `webpage_design/` from accidental overwrite; enforce CLAUDE.md iterative loop on `Stop` event
2. **Add LangSmith tracing** (read-only, no code changes required to routes) — instrument with `LANGCHAIN_TRACING_V2=true` env var around existing Python calls
3. **Build `biomate-mcp-server`** stub: expose `/api/workflows/search` and `/api/runs/:id/status` as MCP tools — enables external integrations immediately

### Medium Term (next 2 sprints)
4. **`report-writer` subagent** as first Deep Agent component — highest user value, lowest risk (purely additive)
5. **LangGraph Memory Store** replacing SQLite session memory — enables cross-session context without UI changes
6. **NCBI/SRA MCP server** — eliminates the biggest user friction (manually finding accession IDs)

### Long Term (v2 roadmap)
7. **Full Deep Agent orchestrator migration** — replace `galaxy-assistant.ts` backbone
8. **BioMate Claude Code plugin** — ship the skill library as an installable plugin
9. **Evaluate Claude Managed Agents** only for stateless, short-running tasks (query understanding, parameter explanation) — not for workflow execution

### Do NOT Pursue
- **Claude Managed Agents for workflow execution** — architecturally incompatible with AWS Batch, GPU requirements, and S3 I/O model
- **Big-bang rewrite** — incremental migration preserves the working E2E test suite and prevents regression

---

## 5. Reference Files

- Claude Code plugin reference: `/home/yzhang/biomate/reference/claude-code/plugins/`
- Hook examples: `/home/yzhang/biomate/reference/claude-code/examples/hooks/`
- Deer-flow skills: `/home/yzhang/biomate/reference/deer-flow/skills/`
- Claude Managed Agents: https://platform.claude.com/docs/en/managed-agents/overview
- LangChain Deep Agents: https://docs.langchain.com/oss/python/deepagents/overview
- Prior architecture doc: `docs/20260406_ARCHITECTURE_FINDINGS_AND_PLANS.md`
