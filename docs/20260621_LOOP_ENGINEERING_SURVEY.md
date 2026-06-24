# Loop Engineering Survey — 2026-06-21

## What "Loop Engineering" Is

Three nested loops are emerging in BioMate. I (Claude Code via MCP) am now
wired into all three.

---

## Loop 1 — The MCP Tool Loop (newly live)

`.mcp.json` at repo root connects Claude Code to a BioMate MCP server:

```
/Users/kky/biomate-connectors-v2/backend/lib/mcp/biomate_mcp_server.py
```

Transport: stdio JSON-RPC 2.0. Target: `http://localhost:5000`.

### Tool tiers

| Tier | Tool | What it does |
|---|---|---|
| 1 — agentic | `biomate_session` | Natural-language goal → workflow selection → AWS Batch run → streamed SSE progress → findings |
| 2 — workflow | `search_workflow` | Search 2,455 indexed workflows by intent |
| 2 | `run_workflow` | Launch by workflow id + explicit params |
| 2 | `get_run` | Poll / stream run status |
| 2 | `get_workflow_spec` | Full param schema for a workflow |
| 3 — outputs | `preview_file` | Render S3 output (table/image/text) |
| 3 | `analyze_results` | Post-run analysis |
| 3 | `export_report` | Pull final report |
| 3 | `query_database` | Query UniProt / PDB / NCBI |
| 3 | `upload_file` | Presigned S3 PUT URL |
| 3 | `recall_memory` | Fetch prior experiment context |

Single source of truth for tool schemas:
`biomate-connectors-v2/backend/lib/mcp/tools_manifest.py`

The Node.js proxy routes that back these tools were added in the current
`integration/next-phase` diff (`frontend/server/routes.ts` +118 lines):
`GET /api/workflows/spec`, `POST /api/files/preview`,
`POST /api/databases/query`, `POST /api/uploads/signed_url`.

---

## Loop 2 — The Auto-Loop QC Loop (established)

Runs after every Nextflow process completion for drug-discovery domains
(ADMET, docking, CYP-DDI, NCA-PK, PBPK) and cryo-EM.

```
Nextflow completion
  → NextflowQCGateHandler   (backend/lib/galaxy/jobs/qc_trace_monitor.py:883+)
  → autoloop_bridge.evaluate_and_emit()   (backend/experiments/autoloop_bridge.py)
  → domain evaluator + enriched_tuner  (backend/experiments/{domain}_autoloop/)
  → SSE events: autoloop_gate_results / autoloop_update / autoloop_escalation
  → AutoLoopPanel (frontend/client/src/components/auto-loop-panel.tsx)
```

Does **not** auto-restart workflows. Emits parameter-delta suggestions
("was → now") for the user to apply on a fresh run.

REST API for stored suggestions:
- `GET  /api/invocations/{id}/autoloop-suggestions`
- `POST /api/invocations/{id}/autoloop-dismiss`

---

## Loop 3 — The Bioconductor Skill Chain (actively evolving)

`bioconductor_skill` submodule (head moved to `4696060` in current branch).
Recent commit trail: "rationale narrator handoff — chain runner one-wire
integration". Implements: skill selection → Bioconductor execution →
interpretation/rationale chain as a multi-step flow for R/Bioconductor
analysis tasks.

---

## Collaboration Model

| Who | Role |
|---|---|
| User | Drives the science goal — what compound, dataset, question |
| Claude Code | Operates the loop: search workflow → launch → monitor SSE → read QC gates → preview outputs → suggest next delta |

Concrete sequence:
1. `search_workflow` — find the right workflow for the goal
2. `run_workflow` or `biomate_session` (streaming) — launch on AWS Batch
3. Watch SSE phase/step events via `get_run`
4. Read auto-loop gate results (Loop 2 fires automatically)
5. `preview_file` / `analyze_results` — inspect outputs
6. Propose parameter remediation or follow-on run

---

## API Key — How Auth Works for MCP

### Short answer

`BIOMATE_API_KEY` in `.mcp.json` can be **empty for anonymous calls**.
All MCP-facing routes use `optionalAuth` middleware, which silently
continues without a user if no token is present:

```ts
// frontend/server/auth-middleware.ts:105-109
if (!token) {
  // No token, continue without user
  next();
  return;
}
```

### Why a real token is needed for billing

When `req.user` is undefined, the billing middleware has no `userId` to
attribute costs to. LLM token usage, vCPU-hours, and GPU-hours are only
recorded to Lago when `req.user.id` is present. Running workflows without
a token means costs are untracked.

### How to get the token

```bash
curl -s -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"lifeifei163361@163.com","password":"<E2E_FIXTURE_PASSWORD>","rememberMe":true}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])"
```

`rememberMe: true` → JWT lives 30 days. Paste the printed token into
`.mcp.json`:

```json
{
  "mcpServers": {
    "biomate": {
      "type": "stdio",
      "command": "python3",
      "args": ["/Users/kky/biomate-connectors-v2/backend/lib/mcp/biomate_mcp_server.py"],
      "env": {
        "BIOMATE_API_URL": "http://localhost:5000",
        "BIOMATE_API_KEY": "<token>"
      }
    }
  }
}
```

The MCP server sends it as `Authorization: Bearer <token>` on every
request. `optionalAuth` picks it up, verifies the JWT, and populates
`req.user` — billing attribution then works on every tool call.

### The `x-e2e-test-token` header is unrelated

That header only bypasses **rate limits** and **quota middleware**
(`rate-limit.ts`, `quota-middleware.ts`, `security-config.ts`). It has
no effect on auth or billing user attribution.
