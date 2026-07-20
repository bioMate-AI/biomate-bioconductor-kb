# OSS Architecture Review: open-science, Auto-Deep-Research, openwork

**Date:** 2026-07-11  
**Purpose:** Understand architecture of comparable open-source AI research tools and identify patterns BioMate can adopt.

---

## 1. open-science — `ai4s-research/open-science`

**URL:** https://github.com/ai4s-research/open-science

**Problem:** Scientists bounce between chat, notebooks, terminal, and writing tools with no provenance trail. Open Science Desktop unifies explore → survey → experiment → write into one auditable session where every artifact links back to the exact code, inputs, model output, and conversation that produced it.

**Stack:** Tauri 2 + React + TypeScript (identical to BioMate Desktop).

**Architecture:**
- **Desktop layer:** Tauri 2 shell + React UI. Never calls the model directly — all model interaction routes through `packages/sdk/OpenCodeClient`
- **Runtime layer:** Bundled OpenCode sidecar (Rust) handles all LLM calls; UI is model-agnostic by construction
- **Skills layer:** Four composable, sequentially-chained research skills (`explore → survey → experiment → write`), each producing an inspectable artifact (PDF survey, runnable notebook, figure) dropped into the workspace
- **Provenance:** `.openscience/provenance.jsonl` — append-only JSONL linking every output artifact to the run that produced it; SQLite index for queries
- **External data:** MCP servers for arXiv, PubMed, Materials Project — the tool layer is pure MCP, no vendor lock-in

**Standout design choices:**
1. **Artifact-first, not chat-first** — Each pipeline stage produces a PDF, notebook, or figure, not a text summary. The pipeline is a series of real, inspectable artifacts.
2. **Model-agnostic by construction** — Swapping Claude → DeepSeek requires no UI changes; the sidecar abstracts the provider.

---

## 2. Auto-Deep-Research — Two variants

### 2a. HKUDS/Auto-Deep-Research
**URL:** https://github.com/HKUDS/Auto-Deep-Research

**Problem:** Self-hosted, provider-agnostic replacement for OpenAI Deep Research.

**Architecture:** Three-agent Magentic-one design (Orchestrator + specialized workers) inside Docker. LiteLLM for provider abstraction — one env var switches the model backend. Browser-enabled container with cookie import for authenticated paywalled sources. Single `auto deep-research` CLI command.

**Standout:** Zero-config deployment; model backend is fully swappable without UI changes.

---

### 2b. AutoResearchClaw — `aiming-lab/AutoResearchClaw`
**URL:** https://github.com/aiming-lab/AutoResearchClaw

**Problem:** Full end-to-end research factory — from idea to conference-ready paper.

**Architecture:** 23 sequential stages across 8 phases:
> Scoping → Literature → Synthesis → Experiment Design → Execution → Analysis → Writing → Finalization

Key agents:
- **CodeAgent** — multi-phase code generation with AST-validated Python sandbox and self-healing repair loops (up to 10 iterations)
- **BenchmarkAgent** — runs experiments against standard benchmarks
- **FigureAgent** — produces publication-quality figures from results
- **ColliderAgent** — physics simulations

Literature pulled from OpenAlex + Semantic Scholar + arXiv with deduplication.

Three human-approval checkpoints with rollback.

Decision loop at Stage 15 — system autonomously chooses **PROCEED / REFINE / PIVOT**.

**Standout choices:**
1. **VerifiedRegistry anti-fabrication guard** — 4-layer citation verification (arXiv → CrossRef → Semantic Scholar → LLM relevance scoring) prevents hallucinated citations from entering the paper.
2. **Cross-run learning (MetaClaw)** — Captures lessons-learned as reusable skills, reducing retry rate ~25% across runs.

---

## 3. openwork — `different-ai/openwork`

**URL:** https://github.com/different-ai/openwork

**Problem:** Make agentic AI workflows accessible to non-technical teams on local files, without vendor lock-in. Positioned as an open-source alternative to Claude Cowork.

**Stack:** Tauri (macOS/Windows/Linux) + web UI; monorepo with Turbo + pnpm workspaces (same pattern as BioMate frontend).

**Architecture:**
- **Desktop:** Tauri shell communicates via `@opencode-ai/sdk/v2/client`
- **Runtime:** OpenCode orchestrator spawned as a local process (Host Mode) or connected remotely by URL (Client Mode) — same UI binary, two deployment modes
- **Streaming:** SSE for real-time step output; REST for session/prompt management
- **Abstractions:**
  - **Sessions** — isolated execution contexts
  - **Skills** — installable modules under `.opencode/skills`
  - **Templates** — reusable workflow snapshots (closest thing to BioMate's workflow history reuse)
  - **Permissions** — capability-based dialog approvals for file/network access

**Standout choices:**
1. **Host/Client duality** — The same UI binary can either spawn the agent locally or connect to a remote server; no separate builds, no feature divergence between cloud and desktop.
2. **Composable deployment** — Desktop, Slack/Telegram connectors, and headless server all share the same agent runtime without UI re-architecture.

---

## Gap Analysis vs BioMate

| Concept | Source | Current BioMate | Suggested action |
|---|---|---|---|
| **Provenance JSONL per run** | open-science | `step_name` + `input_context` fields on `project_files`; no graph | Add `file_lineage` table: `(input_file_id, run_id, output_file_id, step_name)` written by `save-to-project` |
| **Artifact-first pipeline stages** | open-science | Chat returns text + workflow panel; files appear after run completes | Promote each workflow phase output (QC report → processed file → figure) to a named artifact shown progressively in the Files tab |
| **Anti-fabrication citation guard** | AutoResearchClaw | Literature search returns sources from LLM memory | 3-layer verification: Semantic Scholar → CrossRef → LLM relevance scoring before showing citations |
| **PROCEED / REFINE / PIVOT decision loop** | AutoResearchClaw | QC gate supports PROCEED / RETRY only | Add PIVOT: on repeated failure, system suggests an alternative workflow rather than retrying the same one |
| **Host/Client runtime duality** | openwork | Desktop is client-only (connects to dev-public.biomate.ai) | Host Mode: bundle Node server inside Tauri for fully offline use; same UI, two modes |
| **Skills as installable modules** | openwork + open-science | nf-core workflows are the skill layer, but not user-installable | `.biomate/skills` directory: user-dropped `.nf` scripts or `.ga` files auto-discovered and surfaced in the workflow picker |

---

## Priority recommendation

Highest leverage for BioMate's current phase (bioinformatics research users, not general AI):

1. **Provenance graph** (file_lineage table) — directly answers "what produced this file?" for multi-step pipelines; all the pieces are in place (run_id, project_files, step_name)
2. **Anti-fabrication citation guard** — literature search is already a core BioMate feature; hallucinated citations are a credibility risk with faculty users
3. **PROCEED / REFINE / PIVOT** — the QC auto-loop already exists; PIVOT is a one-concept extension that would make the autonomous research loop actually close
