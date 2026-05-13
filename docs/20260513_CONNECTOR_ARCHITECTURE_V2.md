# BioMate Connector Architecture v2

**Date:** 2026-05-13
**Branch:** `claude/improve-connector-architecture-L0eAL`
**Supersedes:** `docs/20260412_BIOMATE_TOOLS_CAPABILITY_MAP.md` (10-tool CRUD surface)

## Problem

The current connector surface (Claude Code / Claude Desktop / Cursor MCP, Open
Claw, Slack, WeChat, and a planned ChatGPT GPT + Codex) exposes **10 CRUD-shaped
tools**. An audit against the platform shows **243 of 253 Express endpoints
unexposed (~96%)** — entire domains (memory, findings, QC profiles, parameter
templates, experiments, workflow chains, methods reports) have **zero** tool
coverage. The 10 tools also force the host model to drive a polling loop and
re-implement the workflow panel, which works poorly in surfaces without rich
rendering (Codex CLI, Slack, WeChat).

The fix is not "ship 50 tools." It is:

1. One **streaming agentic tool** (`biomate_session`) that hands the host the
   SSE event stream BioMate already drives its own UI with.
2. A **tightened primitive surface** (~14 tools) for power users and scripts.
3. A **single source of truth** for tool schemas, consumed by every surface.
4. A **Skill bundle** for Claude that carries the catalog, render templates,
   and OAuth wiring.
5. A **uniform OAuth 2.1 + PKCE** flow for credentials across all surfaces.

## Audit Summary

| Domain | Endpoints | Exposed Today | Gap |
|---|---|---|---|
| Workflows | 48 | 10 | Auto-loop, params lookup, QC profiles, chaining, cost estimation |
| Memory | 27 | 0 | Full gap — projects, episodes, procedures, recall |
| Galaxy | 24 | 0 | Tool catalog, dataset browse, job control |
| Findings & Reports | 6+ | 1 (text-only) | Structured findings, methods/QC reports, PDF export |
| Parameters | 7 | 0 | Templates, validated presets, popularity |
| QC Profiles | 3+ | 0 | Threshold lookup, gate definitions, overrides |
| Outputs | 5 | 1 | File preview/parsing |
| Auth / Billing / Admin | 37 | 0 | **Intentionally out of scope** (security boundary) |
| Interactive Compute | 3 | 0 | Session-based (Jupyter/RStudio) |

(See `Explore` agent audit output 2026-05-13 for the full breakdown.)

## Proposed Tool Surface — 14 tools, 3 tiers

### Tier 1 — Agentic (the wow tool)

| Tool | Purpose | Streaming |
|---|---|---|
| `biomate_session` | Natural-language goal → BioMate orchestrates search + run + analyze + report. Streams the SSE event timeline (`phase`, `step`, `qc_gate`, `auto_loop`, `finding`, `report`) as MCP `notifications/progress`. | **Yes** |

This is the only tool a casual user ever needs. Each progress event carries:

```json
{
  "kind": "phase_started" | "step_completed" | "qc_gate" | "auto_loop_remediation" | "finding" | "done",
  "summary_md": "## Phase 2: Variant calling\n- ✓ BWA-MEM alignment …",
  "view_url": "https://biomate.ai/runs/abc123#phase-2",
  "thumbnail_png_b64": "…",   // optional, for QC cards / findings
  "delta": { … }              // raw structured payload for advanced clients
}
```

Host rendering:
- **Claude Code / Claude Desktop**: progress lines inline, thumbnails rendered.
- **Codex CLI / Slack / WeChat**: markdown summary + link; thumbnails dropped.
- **ChatGPT**: markdown summary + link; on GPT-4o image rendering when present.

### Tier 2 — Workflow primitives (kept / tightened)

| Tool | Status | Notes |
|---|---|---|
| `search_workflow` | Keep | 2,455 workflows; ranked by domain similarity. |
| `get_workflow_spec` | **New** | Replaces ad-hoc param discovery: returns required+optional params with allowed values, default QC profile, cost estimate, license requirements. One call before `run_workflow`. |
| `run_workflow` | Keep | Add `stream: bool` — when true, returns `notifications/progress` like `biomate_session`. |
| `cancel_run` | Keep |
| `list_runs` | Keep | Add `experiment_id` filter. |
| `get_run` | **Merged** | Replaces `get_run_status` + `get_run_results` + step-level findings. Returns one structured payload with status, phases, steps, findings, output files. |

### Tier 3 — Outputs, analysis, reporting

| Tool | Status | Notes |
|---|---|---|
| `preview_file` | **New** | Server-side preview/parse of an output file (FASTA / VCF / CSV / image / PDF). Returns markdown + thumbnail. Replaces today's `analyze_file` for output files. |
| `export_report` | **New** | Render methods report + QC audit + findings as PDF or markdown. The one users actually want for IND/CRO submissions. |
| `analyze_results` | Keep | AI interpretation, free-form. |
| `explain_error` | Keep | AI root-cause diagnosis. |
| `query_database` | Keep | UniProt/PDB/AlphaFold/NCBI/ChEMBL/etc. |
| `recall_memory` | **New** | Retrieve relevant prior runs, findings, procedures for the current goal. The killer feature for repeat users. |
| `upload_file` | **New** | Returns a one-shot signed S3 PUT URL. The host PUTs locally without proxying bytes through the MCP transport. |

### Removed / merged

- `get_run_status`, `get_run_results` → merged into `get_run`.
- `analyze_file` for output files → handled by `preview_file`. For ad-hoc upload analysis it folds into `upload_file` + `analyze_results`.

## Single source of truth

Today the schema lives in two places (`OPEN_CLAW_TOOLS` in
`frontend/server/routes.ts:636` and `TOOLS` in
`backend/lib/mcp/biomate_mcp_server.py:66`). They drift. Fix:

- **`backend/lib/mcp/tools_manifest.py`** — one Python module with the canonical
  schema, as `dataclass` objects + a JSON exporter.
- MCP server imports and serves it directly.
- Node.js (`frontend/server/routes.ts`) loads `tools_manifest.json` (built from
  the Python module at boot) into `OPEN_CLAW_TOOLS`.
- Slack/WeChat already proxy through `/api/open-claw/stream`, so they pick up
  the new tools automatically (no code change there).
- ChatGPT GPT Action manifest, Skill catalog, and `docs/.../CAPABILITY_MAP.md`
  are all generated from the same module.

A drift test in CI fails if the two files are out of sync.

## Streaming over MCP

MCP supports `notifications/progress` (server → client) keyed by a `progressToken`
attached to the request. Implementation outline for `biomate_session`:

1. Client calls `tools/call biomate_session {goal: "screen these SMILES…"}`
   with `_meta.progressToken: "tok-xyz"`.
2. Server connects to BioMate's internal SSE bus
   (`/api/open-claw/stream` or a new `/api/runs/:id/events`).
3. For each SSE event, server emits:
   `{"method": "notifications/progress",
     "params": {"progressToken": "tok-xyz", "progress": <n>, "total": <total>,
                "message": <summary_md>, "_meta": {<delta>}}}`
4. On terminal event, server returns the `tools/call` result with the final
   summary, deep link, and (where supported) PDF report attachment.

For surfaces without progress (Codex, ChatGPT GPT Actions, Slack, WeChat):
expose a paired tool `poll_run(run_id, since_event_id)` that returns the same
event payloads as a delta list. The model loops on it. Same backend code path,
same event shape — only the transport differs.

## Credentials

One identity service, six surface adapters. OAuth 2.1 + PKCE on BioMate with
scope-per-surface tokens.

| Surface | Storage | Flow |
|---|---|---|
| Claude Code | MCP `env` block, OS keychain via Claude Code's secret API | `npx @biomate/connect claude-code` → opens browser → writes refresh token |
| Claude Desktop | Same | Same |
| Cursor | Same | Same |
| Codex CLI | `~/.codex/credentials.json`, OS keychain | `codex install biomate` |
| Claude.ai (Skill) | None on disk; Skill prompts OAuth popup; 30-min JWT in memory | First call to `biomate_session` → "Connect BioMate" |
| ChatGPT Actions | Native OAuth in Actions manifest | Built-in |
| Slack / WeChat | `slack_user_id → biomate_user_id` mapping table + per-user OAuth token in BioMate DB | `/biomate login` slash command |

Scopes: `runs:read runs:write workflows:search billing:read memory:read memory:write`.
Tokens bound to surface fingerprint; revocable per-surface from the BioMate
account page.

## Skill bundle for Claude

Directory `skills/biomate/`:

- `SKILL.md` — instructions: when to call `biomate_session` vs primitives;
  one-line examples per workflow class (ADMET, RNA-seq, WGS, CryoEM).
- `references/workflow_catalog.md` — top-200 workflows with IDs and one-line
  descriptions, for retrieval without a tools/list round-trip.
- `references/render_templates.md` — markdown templates for findings cards, QC
  gate failures, auto-loop diff. Claude is instructed to format incoming events
  with these templates so the chat surface looks like BioMate's panel.
- `assets/qc_gate_card.html` and `assets/finding_card.html` — server-rendered
  reference cards Claude can display via the file-display capability.
- `scripts/connect.sh` — one-line OAuth installer.

## Popularity strategy

1. **Distribution week**: submit to Anthropic MCP directory, Cursor MCP list,
   Anthropic Skills gallery, OpenAI GPT store, Slack App Directory in the
   same week.
2. **One-line install**: `npx @biomate/connect <host>` for every MCP host;
   `gh-style` PR-style adoption story.
3. **Free tier in-protocol**: first 3 runs without account (anonymous AWS
   Batch, watermarked PDFs). Wow moment before signup.
4. **Demo prompts at top of every README**: paste-and-run ADMET, RNA-seq,
   PBPK, CryoEM examples.
5. **Wow anchor**: live progress stream + deep link to a 3D viewer / live
   panel. Generic "run code" tools are commoditized; running real
   nf-core/sarek or CryoSPARC from a chat is not.

## Rollout

| Phase | Scope |
|---|---|
| Phase 1 (this branch) | Tools manifest + `biomate_session` (streaming) + Skill bundle scaffold |
| Phase 2 | New primitives (`get_workflow_spec`, `get_run`, `preview_file`, `export_report`, `recall_memory`, `upload_file`) + drift CI test |
| Phase 3 | OAuth 2.1 identity service + per-surface installers (`@biomate/connect`) |
| Phase 4 | ChatGPT GPT Action manifest, Codex installer; submit to all directories |

## Open questions

1. Should `biomate_session` be allowed to span multiple workflow runs in a
   single tool call (e.g. ADMET → docking → MD), or one run per call? Leaning
   one run per call, with `recall_memory` providing continuity.
2. Free-tier abuse: 3 anonymous runs gated by IP + device fingerprint, or
   require email verification with a 24h cooldown?
3. For ChatGPT Actions, do we need a 25-tool limit fallback? Today's surface
   fits well within the limit; the manifest stays slim.
