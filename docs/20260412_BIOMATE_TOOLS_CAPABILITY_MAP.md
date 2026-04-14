# BioMate Tools Capability Map
**Date:** 2026-04-12  
**Scope:** Open Claw, MCP server, Slack bot, WeChat bot  
**Keep in sync with:** `routes.ts` OPEN_CLAW_TOOLS, `biomate_mcp_server.py` TOOLS

---

## The 10 BioMate Tools (Open Claw + MCP)

All four surfaces (Open Claw, MCP, Slack, WeChat) now expose the same 10 tools.

| # | Tool | Category | Backend Endpoint | Description |
|---|------|----------|-----------------|-------------|
| 1 | `search_workflow` | Discovery | `POST /api/workflows/search` | Natural language search of BioMate's 200+ workflow catalog |
| 2 | `run_workflow` | Execution | `POST /api/workflows/execute` | Launch a workflow on AWS Batch; returns `run_id` |
| 3 | `get_run_status` | Execution | `GET /api/workflows/runs/:id/status` | Poll status: pending/running/completed/failed |
| 4 | `get_run_results` | Execution | `GET /api/workflows/runs/:id/outputs` | List output files with download URLs |
| 5 | `cancel_run` | Execution | `POST /api/workflows/runs/:id/cancel` | Stop a running or queued AWS Batch job |
| 6 | `list_runs` | Execution | `GET /api/workflows/runs` | List recent runs with status filter |
| 7 | `analyze_results` | Analysis | `POST /api/workflows/runs/:id/ai/analyze` | AI interpretation of completed run outputs |
| 8 | `explain_error` | Analysis | `POST /api/workflows/explain_error` | AI root-cause diagnosis of failed runs |
| 9 | `analyze_file` | Analysis | `POST /api/data/analyze` | QC metrics for FASTQ/VCF/CSV/FASTA files |
| 10 | `query_database` | Databases | `POST /api/databases/query` | Query 14 biological/chemical databases |

### Database coverage (`query_database`)
`uniprot` · `pdb` · `alphafold` · `ncbi_gene` · `dbsnp` · `clinvar` · `gnomad` · `kegg` · `reactome` · `chebi` · `pubchem` · `hpo` · `omim` · `string`

---

## Messaging Channel Architecture

```
User
 │
 ├── WeChat Work (企业微信)
 │     wechat_bot.py  port 8091
 │     POST /integrations/wechat/message
 │     - HMAC-SHA1 signature verification
 │     - 10-turn conversation history per user
 │     - Immediate XML ACK + async thread
 │     - Workflow card (textcard) if workflow_id found
 │     └──→ _open_claw_query() ──→ POST /api/open-claw/stream
 │
 ├── Slack
 │     slack_bot.py  port 8090
 │     POST /integrations/slack/command  (/biomate slash command)
 │     - HMAC-SHA256 signature verification
 │     - 10-turn conversation history per Slack user_id
 │     - Immediate JSON ACK ("Analyzing…") + async thread
 │     - Block Kit response with "Run in BioMate" button
 │     └──→ _open_claw_query() ──→ POST /api/open-claw/stream
 │
 └── Direct API / MCP / Claude Desktop
       biomate_mcp_server.py  (stdio transport)
       Same 10 tools as Open Claw via JSON-RPC 2.0
       └──→ BioMateClient HTTP ──→ BioMate API endpoints
```

### Open Claw stream (/api/open-claw/stream)

```
POST /api/open-claw/stream
Body: { messages: [{role, content}], system?: string }

SSE events emitted:
  event: tool_call_start     data: { id, name }
  event: delta               data: { text: "..." }
  event: tool_call_complete  data: { id, name, input }
  event: tool_result         data: { tool_use_id, name, result }
  event: complete            data: { iterations }
  event: error               data: { message }

Agentic loop: max 10 iterations
Model: claude-sonnet-4-6
Auth: Bearer JWT (same as web UI — billing applied)
```

---

## BioMate vs Biomni Capability Comparison

| Capability | BioMate | Biomni |
|---|---|---|
| Web UI (chat + workflow viewer) | ✅ Full | ❌ None |
| Messaging (WeChat Work, Slack) | ✅ Open Claw | ❌ None |
| MCP server (Claude Desktop, Cursor) | ✅ 10 tools | ❌ None |
| AWS Batch workflow orchestration | ✅ 200+ workflows | ❌ None |
| Scientific function library | ~50 via Nextflow | ✅ 250+ Python/R |
| Database coverage | 14 via query_database | ✅ 42 via biomni_workflows |
| Auth / billing / user management | ✅ Full | ❌ None |
| Experiment tracking / memory | ✅ 5-tier | ❌ None |
| Instrument event integration | ✅ 5 instrument types | ❌ None |
| Molecular docking (DiffDock, Vina) | ✅ nf-core workflow | ✅ run_diffdock_with_smiles |
| MD simulation (GROMACS, AMBER) | ✅ AWS Batch | ❌ None |
| CryoEM SPA / CryoET | ✅ CryoSPARC, RELION | ❌ None |
| ADMET / pharmacology | ✅ 10+ workflows | ✅ 30 pharmacology fns |
| Drug repurposing ranking | ✅ assay_ingestion_and_ranking | ✅ retrieve_topk_repurposing |

**Summary**: BioMate is the platform (infrastructure, UI, orchestration). Biomni is a function library. 
BioMate already wraps Biomni's capabilities into Nextflow workflows and exposes them via its tool surface.

---

## What's NOT exposed through tools (intentionally)

These BioMate capabilities are available in the web UI but not in the tool surface:

| Capability | Reason not a tool |
|---|---|
| File upload (multipart) | Binary data not suitable for text-based tool calling |
| Experiment / project management | Internal bookkeeping; not core scientific function |
| Billing / subscription | Never appropriate for AI tool access |
| Admin / audit logs | Security boundary — server-side only |
| Interactive compute (Jupyter, RStudio) | Session-based, not request-response |
| QC governance (prereq checklist) | Applied automatically during run_workflow |

---

## Environment Variables for Messaging Bots

### WeChat bot
```bash
WECHAT_CORP_ID=<企业ID>
WECHAT_CORP_SECRET=<应用密钥>
WECHAT_TOKEN=<接收消息Token>
WECHAT_ENCODING_AES_KEY=<消息加解密Key>
WECHAT_AGENT_ID=<应用AgentId>
BIOMATE_API_URL=https://api.biomate.ai
BIOMATE_API_KEY=<service-account-api-key>
BIOMATE_DEEP_LINK_BASE=https://app.biomate.ai
```

### Slack bot
```bash
SLACK_BOT_TOKEN=xoxb-...
SLACK_SIGNING_SECRET=<signing-secret-from-slack-app>
BIOMATE_API_URL=https://api.biomate.ai
BIOMATE_API_KEY=<service-account-api-key>
BIOMATE_DEEP_LINK_BASE=https://app.biomate.ai
```

### Start commands
```bash
# WeChat bot (port 8091)
gunicorn 'backend.lib.integrations.wechat_bot:create_flask_app()' -w 2 -b 0.0.0.0:8091

# Slack bot (port 8090)
gunicorn 'backend.lib.integrations.slack_bot:create_flask_app()' -w 2 -b 0.0.0.0:8090
```

### E2E test start commands
```bash
# Start with test credentials for E2E
WECHAT_TOKEN=test_token BIOMATE_API_URL=http://localhost:5000 \
  python backend/lib/integrations/wechat_bot.py --port 8091

SLACK_SIGNING_SECRET=test_secret BIOMATE_API_URL=http://localhost:5000 \
  python backend/lib/integrations/slack_bot.py --port 8090

# Then run the test suite
npx playwright test messaging-integration.e2e.ts
```
