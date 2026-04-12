# 2026-04-12 — Session 4 Complete: Integration Layer Documentation

## Overview

Session 4 built BioMate's external integration layer: MCP server, messaging channels (Open Claw, Slack, WeChat), instrument connectors for 12 instrument classes, and SOC2/HIPAA safety infrastructure. This document records what was built, how each piece works, what's next, and how the pieces fit together.

---

## Track 4A — MCP Server

### What Exists (Pre-Session)

`backend/mcp/biomate_mcp_server.py` — v1.1.0, already complete:

| Tool | What it does |
|------|-------------|
| `chat` | Natural-language → BioMate AI SSE stream; returns text + workflow definition + run_id |
| `search_workflows` | SQLite FTS query against the 2,100+ workflow registry |
| `get_workflow_params` | Reads `nextflow_schema.json` for typed parameter schema |
| `list_runs` | Recent runs via `/api/invocations` |
| `get_run_status` | Polls Nextflow status endpoint |
| `get_output_files` | Lists outputs with download URLs |
| `upload_file` | Uploads file to BioMate dataset store |
| `research_query` | PubMed / Semantic Scholar synthesis |
| `rerun_workflow` | Nextflow `-resume` restart |

**Also pre-existing:**
- `backend/tools/biomate_ai_tools/mcp_client.py` — calls AlphaFold + Chai-1 MCP servers
- `backend/biomni_workflows/galaxy/tools/biomni/_lib/lab_automation.py` — PyLabRobot / Hamilton STAR integration with full simulation testing
- `backend/biomni_workflows/galaxy/tools/biomni/_lib/example_mcp_tools/pubmed_mcp.py` — FastMCP PubMed server
- `backend/nf-core-workflows/ops/.mcp.json` — Pulumi MCP server config

### What Was Added This Session

`backend/lib/mcp/mcp_config.json` — updated to point to real server, documents all 8 tools, Claude Desktop config template, lab_automation notes, and the related AlphaFold/Chai-1/PubMed MCP servers.

`backend/lib/mcp/__main__.py` — shim that forwards `python -m backend.lib.mcp` to the real server.

### How to Use

```bash
# Add to Claude Code CLI
claude mcp add biomate -- python3 /path/to/biomate/backend/mcp/biomate_mcp_server.py

# Claude Desktop (~/Library/Application Support/Claude/claude_desktop_config.json)
{
  "mcpServers": {
    "biomate": {
      "command": "python3",
      "args": ["/path/to/biomate/backend/mcp/biomate_mcp_server.py"],
      "env": {
        "BIOMATE_URL": "http://localhost:5000",
        "BIOMATE_API_TOKEN": "<your-jwt-token>"
      }
    }
  }
}

# Smoke test
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | \
  python3 backend/mcp/biomate_mcp_server.py
```

Then from Claude Code:
```
"Run WGS germline variant calling on sample SRR1518169"
"Search BioMate for CRISPR screen workflows"
"What's the status of my last workflow run?"
```

---

## Track 4B — Open Claw + Messaging Channels

### Architecture: Three Layers

```
┌─────────────────────────────────────────────────────────┐
│  CHANNELS (how users reach BioMate)                     │
│  ┌──────────┐  ┌──────────┐  ┌─────────┐  ┌─────────┐  │
│  │ Web UI   │  │  Slack   │  │ WeChat  │  │  MCP    │  │
│  │ (browser)│  │  /biomate│  │  Work   │  │  stdio  │  │
│  └────┬─────┘  └────┬─────┘  └────┬────┘  └────┬────┘  │
│       │             │              │              │       │
├───────┼─────────────┼──────────────┼──────────────┼───────┤
│  MODES (how AI reasoning works)                         │
│  ┌──────────────────────┐   ┌──────────────────────┐   │
│  │  Normal Mode         │   │  Open Claw Mode       │   │
│  │  /api/chat/stream    │   │  /api/open-claw/stream│   │
│  │  BioMate AI layer    │   │  Raw Claude API       │   │
│  │  (intent routing,    │   │  + BioMate tools as   │   │
│  │   param fill, QC)    │   │   visible function    │   │
│  │                      │   │   calls (tool_use     │   │
│  │                      │   │   blocks shown to user│   │
│  └──────────────────────┘   └──────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

**Key distinction:** Open Claw is a *mode* (engine), not a channel. WeChat and Slack are *channels* that currently use Normal Mode. Any channel could be upgraded to use Open Claw as its backend.

### Sub-track 4B-i: Open Claw (Power-User Mode)

**Files:** `frontend/server/routes.ts` (lines 621–, 8599–)

**Endpoints:**
- `GET /api/open-claw/tools` — returns `OPEN_CLAW_TOOLS` (5 Anthropic tool schemas)
- `POST /api/open-claw/stream` — SSE agentic loop, MAX_ITERATIONS=10

**Tools exposed:**
1. `search_workflow(query)` → calls `/api/workflows/search`
2. `run_workflow(workflow_id, params)` → calls `/api/workflows/execute`
3. `get_run_status(run_id)` → calls `/api/invocations/:id/nextflow/status`
4. `get_run_results(run_id)` → calls `/api/invocations/:id/outputs`
5. `analyze_file(file_path)` → calls `/api/open-claw/analyze-file`

**Security:** All tool calls go through BioMate's auth layer. `optionalAuth` on both routes — anonymous can explore, authenticated users get per-user context.

**Frontend TODO:** A raw conversation panel component that renders `tool_use` blocks visibly (not hidden like in Normal Mode). The backend is ready; the frontend UI is the remaining work.

### Sub-track 4B-ii: WeChat Work (企业微信)

**File:** `backend/lib/integrations/wechat_bot.py`

**Deployment:** Standalone Flask app on port 8091, separate from the main BioMate server.

```bash
python backend/lib/integrations/wechat_bot.py --port 8091
```

#### Setup (One-Time)

1. Go to [work.weixin.qq.com](https://work.weixin.qq.com) → Application Management → create/open your app
2. Under **"Receive Messages"** → **"Set API"**:
   - API URL: `https://your-domain/integrations/wechat/message`
   - **Token**: any string you choose (e.g. `python3 -c "import secrets; print(secrets.token_urlsafe(20))"`) — this is `WECHAT_TOKEN`
   - **EncodingAESKey**: click "Auto-generate" — this is `WECHAT_ENCODING_AES_KEY`
3. From Settings → Enterprise Info: **Company ID** = `WECHAT_CORP_ID`
4. From app Basic Info: **App Secret** = `WECHAT_CORP_SECRET`, **AgentId** = `WECHAT_AGENT_ID`

#### Environment Variables

```bash
WECHAT_CORP_ID=your_corp_id
WECHAT_CORP_SECRET=your_app_secret
WECHAT_TOKEN=your_chosen_token
WECHAT_ENCODING_AES_KEY=your_aes_key
WECHAT_AGENT_ID=your_agent_id
BIOMATE_API_URL=http://localhost:5000
BIOMATE_DEEP_LINK_BASE=https://app.biomate.ai
```

#### How It Works

User sends WeChat message → BioMate searches workflows → replies with WeChat text card containing "Open in BioMate" deep link.

Commands:
- `bind <api_key>` — link WeChat account to BioMate
- `unbind` — remove binding
- `help` / `帮助` — show available commands
- Any other text → async workflow search → up to 3 workflow cards

#### Security Controls Added This Session

- `WECHAT_TOKEN` is **mandatory** — returns 503 if not set (was previously skippable)
- All three security params (`timestamp`, `nonce`, `msg_signature`) checked before any XML parsing
- Signature failure logs remote IP

### Sub-track 4B-ii: Slack

**File:** `backend/lib/integrations/slack_bot.py`

**Deployment:** Standalone Flask app on port 8090.

```bash
python backend/lib/integrations/slack_bot.py --port 8090
```

**Setup:**
1. Create Slack App at api.slack.com/apps → Slash Commands → `/biomate`
2. Request URL: `https://your-domain/api/biomate`
3. Signing Secret → `SLACK_SIGNING_SECRET`
4. Bot token from OAuth page → `SLACK_BOT_TOKEN`

**How it works:** `/biomate run ADMET screening on this compound list` → Block Kit card with "Run in BioMate" button.

---

## Track 4C — Instrument Connectors

### Architecture

All connectors follow the same pattern:
```
Instrument output directory
    ↓ (file watcher daemon, polling every 30–120s)
Connector (detect vendor, parse metadata, detect experiment type)
    ↓
POST /api/instruments/new-data  ← BioMate creates session + notifies user
    ↓
BioMate workflow pre-filled with instrument parameters
    ↓ (user clicks Run)
Nextflow execution on AWS Batch
    ↓
Analysis using existing _lib/ functions
```

### Connector Index

| File | Instruments | Detected experiments | Bridges to |
|------|-------------|---------------------|------------|
| `opentrons_connector.py` | OT-2, Flex (HTTP :31950) | Protocol push / run monitor | PyLabRobot Hamilton backend |
| `benchling_connector.py` | Benchling ELN/LIMS (REST OAuth2) | Pull samples + entries; push results | `assay_ingestion_and_ranking` |
| `illumina_basespace_connector.py` | NovaSeq, NextSeq (OAuth2) | WGS, RNA-seq, amplicon | `wgs_germline_gatk`, `rnaseq_differential` |
| `nanopore_minknow_connector.py` | MinION, PromethION (HTTP :9501) | POD5/FAST5 run complete | `nanopore_basecalling` |
| `instrument_watcher.py` | Generic file watch | CryoEM (.mrc), Nanopore (.pod5), FASTQ, mzML, .RAW | 5 Nextflow workflows |
| `cryoem_instrument_connector.py` | Titan Krios, Talos (EPU REST + file) | Session complete (movies, pixel size, voltage) | `cryosparc_standard_spa` |
| `lcms_connector.py` | Thermo Xcalibur (.raw), Waters (.raw dir), Bruker (.d), SCIEX (.wiff) | Proteomics, metabolomics, lipidomics | `diann_proteomics`, `xcms_metabolomics` |
| `sila2_adapter.py` | Hamilton, Tecan, centrifuges, plate readers (SiLA2 gRPC) | Any SiLA2 command/property | Generic device control |
| `flow_cytometer_connector.py` | BD FACSDiva, CytoFLEX, MACSQuant (.fcs) | Immunophenotyping, CFSE, cytokine ICS, apoptosis, sort | `cell_biology.analyze_flow_cytometry_immunophenotyping`, `immunology.analyze_cfse_cell_proliferation` |
| `plate_reader_connector.py` | BMG CLARIOstar, BioTek Gen5, SpectraMax (.csv/.txt) | Enzyme kinetics, dose-response/IC50, ELISA, cell viability | `biochemistry.analyze_enzyme_kinetics_assay`, `dose_response` |
| `qpcr_connector.py` | CFX Manager (.pcrd), QuantStudio (.eds), LightCycler (.ixo) | RT-qPCR, CRISPR screen qPCR, ChIP-qPCR, genotyping | `molecular_biology.pcr_simple`, `genetics.perform_pcr_and_gel_electrophoresis` |
| `slack_bot.py` | Slack slash command | Natural language → workflow card | Normal Mode AI |
| `wechat_bot.py` | WeChat Work webhook | Natural language → workflow card | Normal Mode AI |

### How to Deploy in Practice

#### Step 1: Environment Variables

Create `/etc/biomate/instrument.env` on each analysis server:

```bash
# Common
BIOMATE_API_URL=https://app.biomate.ai   # or http://localhost:5000 for local
BIOMATE_API_KEY=<service-account-token>  # Settings → API Keys → create service account

# CryoEM server (Krios room PC or analysis workstation)
EPU_OUTPUT_DIR=/mnt/krios1/data
CRYOEM_POLL_INTERVAL=60

# Sequencer server
INSTRUMENT_WATCH_DIRS=/mnt/illumina/runs:/mnt/nanopore/runs
MINKNOW_HOST=sequencer01.local
LCMS_WATCH_DIRS=/mnt/xcalibur/data

# Flow cytometry / plate reader (lab PC or shared analysis server)
FLOW_CYTOMETER_WATCH_DIRS=/mnt/facsdiva/export
PLATE_READER_WATCH_DIRS=/mnt/gen5/export
QPCR_WATCH_DIRS=/mnt/cfx/export
```

#### Step 2: Start Watchers (systemd)

```ini
# /etc/systemd/system/biomate-instruments.service
[Unit]
Description=BioMate Instrument Watchers
After=network.target

[Service]
EnvironmentFile=/etc/biomate/instrument.env
ExecStart=/usr/bin/python3 /opt/biomate/backend/lib/integrations/instrument_watcher.py \
    /mnt/krios1/data /mnt/illumina/runs /mnt/nanopore/runs
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Or use the docker-compose approach (from prior architecture docs):
```bash
docker-compose -f backend/docker/docker-compose.instruments.yml up -d
```

#### Step 3: BioMate Server Must Have `/api/instruments/new-data`

**This endpoint does not exist yet** — it's the critical missing piece. Without it, all connectors can POST events but nothing handles them.

**What the endpoint needs to do:**
1. Accept the event JSON from any connector
2. Create/find a BioMate session for the user or a shared lab account
3. Pre-fill workflow parameters from the event (`movies_path`, `fcs_dir`, `mzml_dir`, etc.)
4. Emit a notification to connected frontend clients (SSE or WebSocket)
5. Optionally: auto-submit if the user has auto-run configured

#### Step 4: Frontend Notification Panel

A "New Data" panel in the sidebar that shows pending instrument events with "Run now" / "Dismiss" actions. When the user clicks "Run now", it opens the workflow viewer pre-filled with the instrument parameters.

---

## Track 4D — Safety Guardrails + Audit

### Safety Guardrails

**File:** `frontend/server/safety-guardrails.ts`

**Wired in:** `frontend/server/routes.ts:3367` — runs on every `/api/chat/stream` call before LLM.

**PHI detection patterns:**

| Type | Regex | Action |
|------|-------|--------|
| SSN | `\b\d{3}-\d{2}-\d{4}\b` | Strip + audit |
| Date of Birth | `(DOB|Date of Birth)[:\s]+\d{1,2}[/-]\d{1,2}[/-]\d{2,4}` | Strip + audit |
| MRN | `(MRN|Medical Record)[:\s#]+[A-Z0-9]{4,12}` | Strip + audit |
| Patient ID | `(Patient ID|PatientID|PID)[:\s#]+[A-Z0-9\-]{4,20}` | Strip + audit |
| NPI | `NPI[:\s#]+\d{10}` | Strip + audit |
| Insurance | `(Policy|Member ID)[:\s#]+[A-Z0-9\-]{6,20}` | Strip + audit |

**Content safety rules (multi-signal, no single keyword blocks):**

| Rule | Trigger | Response |
|------|---------|----------|
| `gain_of_function` | ≥3 of: pathogen + enhanced transmissibility + airborne + lethality | Hard refuse |
| `cbrn_synthesis` | ≥2 of: synthesis route + precursor + nerve agent family | Hard refuse |
| `scheduled_substance_synthesis` | drug synthesis + Schedule I keyword + no bio bypass | Hard refuse |
| `clinical_diagnosis` | diagnosis/treatment + patient name token + no research bypass | Warn + audit |

### Audit Logging

**Service:** `frontend/server/audit-service.ts` — `AuditService` class

**Middleware:** Applied at `app.use('/api', auditMiddleware(...))` — logs all API calls automatically.

**Explicit event logging:**
- `auth.login` / `auth.logout` / `auth.register` — on every auth action
- `workflow.execute.start` — when a Nextflow job is submitted
- `safety.block` — when a message is refused by content rules
- `safety.phi_detected` — when PHI is stripped (hash only, not plaintext)
- `api.*` — every API endpoint via middleware (duration, status, IP)

**Admin queries:**
```
GET /api/admin/audit-log?event_type=safety.block&limit=100
GET /api/admin/audit-log/summary
```

**Audit log schema:** `audit_logs` table in PostgreSQL — `id, userId, sessionId, action, resourceType, resourceId, details, reasoning, timestamp, ipAddress, userAgent, status, errorMessage, durationMs`

**Compliance docs:** `docs/20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md`

---

## What's Next (Ordered by Impact)

### P0 — Must do before any instrument connector works

**Implement `/api/instruments/new-data` in `routes.ts`:**

```typescript
app.post("/api/instruments/new-data", optionalAuth, async (req, res) => {
  const event = req.body;
  // 1. Validate event schema (workflow_id, directory/file_path, param_key, message)
  // 2. Find or create a session for the triggering user / lab service account
  // 3. Build pre-filled workflowDefinition from event params
  // 4. Store as a "pending suggestion" in DB (new table: instrument_suggestions)
  // 5. Broadcast to connected clients via SSE or push notification
  res.json({ accepted: true, suggestion_id: newId });
});
```

New DB table needed: `instrument_suggestions(id, timestamp, source, workflow_id, params, status, user_id)`

### P1 — Frontend notification panel

A sidebar or notification bell showing pending instrument suggestions. Each card shows:
- Instrument name + event type
- "Run now" button (opens workflow viewer pre-filled)
- "Dismiss" button
- Timestamp and file count

### P2 — Open Claw frontend component

The backend (`/api/open-claw/stream`) is done. The frontend is missing:
- A raw conversation panel where `tool_use` blocks are visible
- Each tool call shown as an expandable block: `[tool: search_workflow] → [result: 3 workflows found]`
- A toggle in settings: "Normal Mode" vs "Open Claw Mode"

### P3 — WeChat to Open Claw bridge (optional)

Wire `wechat_bot.py` to use `/api/open-claw/stream` instead of `/api/workflows/search`, so WeChat users get the full agentic loop. The Open Claw response (tool_use blocks) would be collapsed into a summary card for WeChat's card format.

### P4 — docker-compose.instruments.yml

The file is referenced in prior architecture docs but was never deployed. Build it:
- One container per instrument class (or a single multi-watcher container)
- Environment variable passthrough
- NFS mount configuration for each instrument share
- Health check endpoints

### P5 — Register new workflow IDs in DB

The connectors reference workflow IDs that may not exist in the registry:
- `flow_cytometry_immunophenotyping`, `flow_cytometry_cytokines`
- `plate_reader_enzyme_kinetics`, `plate_reader_dose_response`
- `qpcr_differential_expression`, `qpcr_quantification`

These need Nextflow `.nf` files + DB registration, or map to existing workflows.

---

## File Map: Session 4 New Files

```
backend/
  mcp/
    biomate_mcp_server.py        ← PRE-EXISTING canonical MCP server (v1.1.0)
  lib/
    mcp/
      __main__.py                ← Shim forwarding to real server
      mcp_config.json            ← Updated: all 8 tools + related servers
    integrations/
      opentrons_connector.py     ← OT-2/Flex HTTP API
      benchling_connector.py     ← Benchling REST OAuth2
      illumina_basespace_connector.py  ← BaseSpace OAuth2 + run list
      nanopore_minknow_connector.py    ← MinKNOW HTTP :9501
      instrument_watcher.py      ← Generic file watcher (CryoEM/Nanopore/FASTQ/mzML)
      sila2_adapter.py           ← SiLA2 gRPC + mDNS discovery
      wechat_bot.py              ← WeChat Work webhook (Flask :8091)
      slack_bot.py               ← Slack slash command (Flask :8090)
      cryoem_instrument_connector.py   ← EPU REST API + session file watcher
      lcms_connector.py          ← Thermo/Waters/Bruker/SCIEX + msconvert
      flow_cytometer_connector.py      ← FCS parser + BD/Beckman/Miltenyi
      plate_reader_connector.py        ← Gen5/MARS/SoftMaxPro + assay detection
      qpcr_connector.py          ← CFX .pcrd (SQLite) + QuantStudio .eds (ZIP)

frontend/
  server/
    safety-guardrails.ts         ← PHI detection + content safety rules
    audit-service.ts             ← AuditService + auditMiddleware (PRE-EXISTING, wired)
    routes.ts                    ← Open Claw routes, safety wired in /api/chat/stream,
                                    audit log admin endpoints

docs/
  20260412_SOC2_HIPAA_AUDIT_FRAMEWORK.md   ← Full compliance reference
  20260412_DOCKER_SHRINK_ANALYSIS.md       ← biomate-interactive + biomni-tools split plan
  20260412_VIRTUAL_LAB_CONNECTOR_SURVEY.md ← 14 systems ranked
  20260412_MCP_SERVER_GUIDE.md             ← Installation + Claude Desktop config
  20260412_SESSION4_INTEGRATION_COMPLETE.md ← This document
```

---

## Cross-Session Dependencies This Work Creates

| Our output | Needed by | Why |
|-----------|-----------|-----|
| `/api/instruments/new-data` (P0 TODO) | Session 5D E2E | E2E test for instrument trigger path |
| Open Claw `/api/open-claw/stream` | Session 5D E2E | Needs E2E test for tool_use visibility |
| Safety guardrails | Session 5D E2E | Must not false-positive on legitimate bio queries |
| Docker image split plan (`biomni-docking`, etc.) | Session 3C | Session 3 wires new AI containers after images exist |
| `audit_logs` table active | SOC2 audit | First 30-day evidence collection window starts now |
