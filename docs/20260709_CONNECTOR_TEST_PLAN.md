# BioMate Connector Test Plan
**6 surfaces · 30 test cases · All tests run against live BioMate backend — no mocks**

---

## Surface Legend

| Surface | Transport | Auth | Entry point |
|---|---|---|---|
| Claude Code | stdio MCP | `BIOMATE_AUTH_TOKEN` in `~/.claude.json` | Type in Claude Code terminal |
| Claude Science | streamable HTTP MCP — **`https://localhost:8001/mcp`** | `Authorization: Bearer <token>` | Settings → MCP Servers → Add URL |
| Codex CLI | stdio MCP | `BIOMATE_AUTH_TOKEN` in `~/.codex/config.toml` | `codex "<prompt>"` |
| ChatGPT | OpenAPI + OAuth 2.1 / PKCE | User OAuth flow | GPT Actions → import `openapi.json` |
| Slack | Slash command `/biomate` | `BIOMATE_API_KEY` service account | `/biomate <query>` in any channel |
| Feishu / Lark | Bot events (`im.message.receive_v1`) | `bind <api_key>` per user | @-mention bot or DM |

> **Claude Science note:** The server must run with `--ssl` (HTTPS). Start with `./mcp/start_http_server.sh` — it auto-generates a self-signed cert at `mcp/localhost.crt` on first run. To suppress the browser trust warning permanently on macOS:
> ```bash
> sudo security add-trusted-cert -d -r trustRoot \
>   -k /Library/Keychains/System.keychain mcp/localhost.crt
> ```
> Then register `https://localhost:8001/mcp` in Claude Science (not `http://`).

---

## 1. Claude Code

**Transport:** stdio MCP · **Tools:** 11 (search_workflow, run_workflow, watch_run, get_run_status, get_run_results, analyze_results, list_runs, upload_file, cancel_run, search_literature, query_database)

### Setup

Add to `~/.claude.json` → `mcpServers.biomate`:

```json
{
  "mcpServers": {
    "biomate": {
      "command": "python3",
      "args": ["/path/to/biomate_mcp_server.py"],
      "env": {
        "BIOMATE_API_URL": "https://dev-public.biomate.ai",
        "BIOMATE_AUTH_TOKEN": "<your token>"
      }
    }
  }
}
```

Restart Claude Code. Verify with `/mcp` — biomate should show green.

---

### TC-CC-1 · Workflow discovery — find ADMET screening pipeline

**Input:**
```
Search BioMate for ADMET screening workflows that predict hERG and CYP3A4 inhibition.
```

**Expected:**
- `search_workflow` called with query `"ADMET hERG CYP3A4"`
- Returns `workflow_ga` with `name`, `domain=drug_discovery`, required params including `smiles` or `compound_list`, `nextflow_path` populated

- [ ] Pass  · [ ] Fail

---

### TC-CC-2 · Run ADMET screening on three compounds

**Input:**
```
Screen these compounds for ADMET using BioMate:
  aspirin    CC(=O)Oc1ccccc1C(=O)O
  ibuprofen  CC(C)Cc1ccc(cc1)C(C)C(=O)O
  caffeine   Cn1cnc2c1c(=O)n(c(=O)n2C)C

Flag any with hERG IC50 < 1 µM or CYP3A4 inhibition > 50%.
```

**Expected:**
- `run_workflow` called → returns `{runId, status:"pending"}`
- `watch_run` polls until `status:"completed"`
- `analyze_results` returns hERG/CYP3A4 values per compound
- QC gate fires if any threshold exceeded

> Expected wall-clock: 3–8 min on AWS Batch. `watch_run` timeout: 600s.

- [ ] Pass  · [ ] Fail

---

### TC-CC-3 · Literature search — hERG cardiotoxicity evidence

**Input:**
```
Search the literature for papers on kinase inhibitor hERG cardiotoxicity and cardiac safety margins. Use BioMate's literature search.
```

**Expected:**
- `search_literature` called with query `"kinase inhibitor hERG cardiotoxicity"`
- Returns ≥ 10 papers with `title`, `authors`, `pmid`/`doi`, `abstract`
- Sources: PubMed + EuropePMC + Semantic Scholar

- [ ] Pass  · [ ] Fail

---

### TC-CC-4 · Database lookup — gene and protein annotation

**Input:**
```
Look up TP53 in BioMate's biological databases. I want UniProt annotation, known cancer mutations from ClinVar, and associated KEGG pathways.
```

**Expected:**
- `query_database` called with `query="TP53"`, `entity_type="gene"`, `database="federated"`
- Fan-out hits UniProt + ClinVar + KEGG
- Returns structured hits from ≥ 2 sources
- No hallucinated data — all values from real DB responses

- [ ] Pass  · [ ] Fail

---

### TC-CC-5 · Run history — list runs and inspect completed one

**Input:**
```
Show me my 5 most recent BioMate workflow runs. For the most recent completed one, show me the output files and key findings.
```

**Expected:**
- `list_runs(limit=5)` returns array with `status`/`workflowName`/`createdAt`
- `get_run_results` called for most recent completed run
- `analyze_results` returns `findings.summary` with real values
- No "run not found" or empty results for completed runs

- [ ] Pass  · [ ] Fail

---

## 2. Claude Science

**Transport:** streamable HTTP MCP on port 8001 · **Tools:** 11 · **Auth:** per-request Bearer token via middleware

### Setup

```bash
BIOMATE_AUTH_TOKEN=<token> python3.11 mcp/biomate_http_server.py
```

In Claude Science: Settings → MCP Servers → Add → `http://localhost:8001/mcp`

Verify connection:
```bash
curl -s http://localhost:8001/mcp \
  -X POST -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer <token>' \
  -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}'
# → 200 with serverInfo
```

---

### TC-CS-1 · Auth gate — unauthenticated request is rejected

**Input:**
```bash
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:8001/mcp \
  -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1,"params":{}}'
```

**Expected:** `401`

- [ ] Pass  · [ ] Fail

---

### TC-CS-2 · Tool discovery — 11 tools visible after auth

**Input:**
```bash
curl -s http://localhost:8001/mcp \
  -H 'Authorization: Bearer <token>' \
  -H 'mcp-session-id: <session-id>' \
  -X POST -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}'
```

**Expected:**
```
{"result":{"tools":[...]}} with exactly 11 tools:
search_workflow, run_workflow, watch_run, get_run_status,
get_run_results, analyze_results, list_runs, upload_file,
cancel_run, search_literature, query_database
```

- [ ] Pass  · [ ] Fail

---

### TC-CS-3 · RNA-seq DE analysis — end-to-end pipeline run

**Input:**
```
Run RNA-seq differential expression using BioMate on these demo samples:
  treated: s3://biomate-demo/rnaseq/treated_R1.fq.gz
  control:  s3://biomate-demo/rnaseq/control_R1.fq.gz
Reference: GRCh38. Single-end reads. Report DEGs at FDR < 0.05.
```

**Expected:**
- `search_workflow` → nf-core/rnaseq or DESeq2 pipeline selected
- `run_workflow` → `runId` returned
- `watch_run` → polls to `completed`
- `analyze_results` → DEG count, top genes, volcano plot path

> Per-request auth: each tool call uses the Bearer token from the initial request — verify no token bleed between concurrent sessions.

- [ ] Pass  · [ ] Fail

---

### TC-CS-4 · Literature + database combined — BRCA1 context

**Input:**
```
Before I run GWAS analysis, look up BRCA1 in biological databases and find recent papers on BRCA1 variants in breast cancer GWAS. Use BioMate.
```

**Expected:**
- `query_database(query="BRCA1", entity_type="gene")` → UniProt P38398 + ClinVar variants + KEGG
- `search_literature(query="BRCA1 breast cancer GWAS variants")` → ≥ 10 papers with abstracts
- Both calls complete without authentication errors

- [ ] Pass  · [ ] Fail

---

### TC-CS-5 · SERVER_INSTRUCTIONS routing — BioMate chosen over generic tools

**Input:**
```
I have a VCF file with somatic variants from a tumor biopsy. I want to annotate them against ClinVar and run a copy-number analysis.
```

**Expected:**
- Claude Science selects BioMate tools (not generic file tools)
- `search_workflow` called for CNV / somatic variant annotation pipeline
- `query_database` called for ClinVar lookup
- `SERVER_INSTRUCTIONS` routing visible in model's tool selection behavior

- [ ] Pass  · [ ] Fail

---

## 3. Codex CLI

**Transport:** stdio MCP · **Tools:** same 11 as Claude Code · **Config:** `~/.codex/config.toml`

### Setup

Add to `~/.codex/config.toml`:

```toml
[mcp_servers.biomate]
command = "python3"
args = ["/path/to/biomate_mcp_server.py"]

[mcp_servers.biomate.env]
BIOMATE_API_URL = "https://dev-public.biomate.ai"
BIOMATE_AUTH_TOKEN = "<your token>"
```

Confirm: `codex --version`. Restart codex after config change.

---

### TC-CX-1 · ADMET screening via natural language CLI prompt

**Input:**
```bash
codex "Screen aspirin, ibuprofen, and naproxen for hERG and CYP3A4 using BioMate. Flag any with hERG IC50 below 1 µM."
```

**Expected:**
- Codex calls `search_workflow` → `run_workflow` → `get_run_status` loop
- Progress events printed inline as delta list
- Final output: per-compound hERG/CYP3A4 values + flag summary
- No fabricated IC50 values — all from real BioMate run

- [ ] Pass  · [ ] Fail

---

### TC-CX-2 · RNA-seq on S3 paths via CLI

**Input:**
```bash
codex "Run RNA-seq DE on the FASTQs at s3://biomate-demo/rnaseq/ — treated vs control, GRCh38 reference. Use BioMate."
```

**Expected:**
- `run_workflow` submitted with correct `s3://` paths as params
- Model polls via `get_run_status` at intervals (not blocking `watch_run`)
- Markdown summary + deep link to `biomate.ai/runs/<id>` printed
- Model does not hallucinate "analysis complete" before run finishes

> Codex doesn't render rich progress UI — model should loop on `get_run_status` rather than `watch_run` (which blocks for up to 600s).

- [ ] Pass  · [ ] Fail

---

### TC-CX-3 · Literature search from CLI

**Input:**
```bash
codex "Find papers on CRISPR base editing off-target effects in primary T cells. Use BioMate literature search."
```

**Expected:**
- `search_literature` called with appropriate query
- Returns ≥ 10 papers printed as numbered list with DOI/PMID
- Titles are real (verifiable via PubMed)
- Response time < 30s

- [ ] Pass  · [ ] Fail

---

### TC-CX-4 · Run status check by run ID

**Input:**
```bash
codex "Check the status of BioMate run <run_id_from_TC-CX-2> and show me the output files if it completed."
```

**Expected:**
- `get_run_status` returns current status
- If completed: `get_run_results` returns output file list with `name`, `extension`, `size`, `download_url`
- No "run not found" error for a valid run ID

- [ ] Pass  · [ ] Fail

---

### TC-CX-5 · Compound database lookup — ChEMBL bioactivity

**Input:**
```bash
codex "Look up imatinib in BioMate's biological databases. I want its ChEMBL bioactivity data and known targets."
```

**Expected:**
- `query_database(query="imatinib", entity_type="compound")` with `database="federated"`
- Fan-out hits ChEMBL + PubChem + UniProt
- Returns IC50/Ki values for BCR-ABL, KIT, PDGFRA targets
- No hallucinated assay values

- [ ] Pass  · [ ] Fail

---

## 4. Slack

**Transport:** slash command + event webhooks · **Auth:** `SLACK_SIGNING_SECRET` per request, `BIOMATE_API_KEY` service account

### Setup

1. Create Slack app at `api.slack.com/apps`
2. Add slash command `/biomate` → `POST https://<host>/integrations/slack/command`
3. Bot Token Scopes: `commands`, `chat:write`, `users:read`
4. Set env vars:

```
SLACK_BOT_TOKEN=xoxb-...
SLACK_SIGNING_SECRET=<from app credentials>
BIOMATE_API_KEY=<service account key>
BIOMATE_DEEP_LINK_BASE=https://app.biomate.ai
```

---

### TC-SL-1 · Empty query → usage message with examples

**Input:** `/biomate`

**Expected:**
- Ephemeral message with usage guide: `"Usage: /biomate <your scientific analysis request>"`
- Lists 3–4 example commands
- Does not call BioMate API
- Response visible only to sender (ephemeral)

- [ ] Pass  · [ ] Fail

---

### TC-SL-2 · ADMET screening request — workflow card returned

**Input:**
```
/biomate run ADMET screening on aspirin, ibuprofen, and naproxen
```

**Expected:**
- Block Kit message posted to channel with:
  - Workflow name header (not "undefined")
  - Brief description of what will run
  - "Run in BioMate" button with valid deep link
  - Domain badge: `drug_discovery`
- Immediate response (async BioMate call in background)

- [ ] Pass  · [ ] Fail

---

### TC-SL-3 · Knowledge query — GWAS variants for a disease

**Input:**
```
/biomate what GWAS variants are associated with rheumatoid arthritis?
```

**Expected:**
- BioMate chat/stream routes to knowledge response
- Block Kit message with top GWAS loci (HLA-DRB1, PTPN22, etc.)
- "View in BioMate" deep link for full context
- Response within 15s (no workflow launched for pure knowledge query)

- [ ] Pass  · [ ] Fail

---

### TC-SL-4 · Run status check by ID

**Input:**
```
/biomate check status of run <run_id>
```

**Expected:**
- Block Kit message showing run ID, workflow name, current status, time elapsed
- "Open run" deep link to `biomate.ai/runs/<id>`
- No "run not found" error for a valid ID

- [ ] Pass  · [ ] Fail

---

### TC-SL-5 · Signature verification — forged request is rejected

**Input:**
```bash
curl -X POST https://<host>/integrations/slack/command \
  -d "command=/biomate&text=run+something" \
  -H "X-Slack-Signature: v0=badsignature" \
  -H "X-Slack-Request-Timestamp: $(date +%s)"
```

**Expected:**
- HTTP `403`
- Body: `{"error": "Invalid Slack signature"}`
- No BioMate API call made
- Slack bot does not respond in channel

- [ ] Pass  · [ ] Fail

---

## 5. Feishu / Lark

**Transport:** bot events (`im.message.receive_v1`) · **Auth:** per-user `bind <api_key>` → open_id linked to BioMate account

### Setup

1. Create custom app at `open.feishu.cn` (Lark: `open.larksuite.com`)
2. Enable bot capability. Scopes: `im:message`, `im:message:send_as_bot`
3. Event subscription URL: `https://<host>/connect/feishu/webhook` → subscribe to `im.message.receive_v1`
4. Set env vars:

```
FEISHU_APP_ID=cli_...
FEISHU_APP_SECRET=<from app credentials>
FEISHU_VERIFY_TOKEN=<event verification token>
BIOMATE_API_KEY=<service account key>
CONNECTOR_PUBLIC_URL=https://connect.example.com   # for HMAC-signed magic-login links
```

---

### TC-FE-1 · Account binding — link Feishu identity to BioMate API key

> Run this AFTER TC-FE-2 to verify unbound path first.

**Input** (DM to BioMate bot):
```
bind bm_live_XqP4X7ack94qoSXxdjgk5imcV-jm7VTh
```

**Expected:**
- Bot replies: `"✅ 已成功绑定 BioMate 账号"`
- `open_id` stored in binding store alongside `api_key`
- Subsequent messages from this user use this `api_key`
- Invalid key → bot replies with error prompt

- [ ] Pass  · [ ] Fail

---

### TC-FE-2 · Unbound user — prompt to bind before analysis

> Run this BEFORE TC-FE-1.

**Input:**
```
@BioMate 帮我跑一个RNA-seq差异表达分析
```

**Expected:**
- Bot replies prompting account binding: `"请先绑定您的 BioMate 账号：bind <api-key>"`
- Includes link to get API key at `biomate.ai/account`
- Does NOT attempt BioMate API call without a key

- [ ] Pass  · [ ] Fail

---

### TC-FE-3 · Workflow request — RNA-seq pipeline card (bound user)

**Input:**
```
@BioMate Run RNA-seq differential expression on tumor vs normal samples in GRCh38.
```

**Expected:**
- BioMate `/api/chat/stream` called with user's bound `api_key`
- Bot replies with workflow name + domain badge + step summary
- "Run in BioMate" card button with HMAC-signed magic deep link (`/connect/feishu/go?...`)
- Magic link is one-time use (expires after click)

- [ ] Pass  · [ ] Fail

---

### TC-FE-4 · Knowledge query in Chinese — literature on gene therapy

**Input:**
```
@BioMate 关于AAV基因治疗免疫原性的最新研究有哪些？
```

**Expected:**
- BioMate interprets Chinese query → literature search executed
- Bot replies with ≥ 3 papers on AAV immunogenicity with verifiable DOIs
- Response in same language as query (Chinese) or bilingual
- No hallucinated paper titles or authors

- [ ] Pass  · [ ] Fail

---

### TC-FE-5 · Unbind — remove account link

**Input** (DM to BioMate bot):
```
unbind
```

**Expected:**
- Bot replies: `"✅ 已解绑 BioMate 账号"`
- `open_id` removed from binding store
- Next message from this user triggers "please bind" prompt
- No `api_key` lingering in memory for this `open_id`

- [ ] Pass  · [ ] Fail

---

---

## 6. ChatGPT

**Transport:** OpenAPI 3.1 + OAuth 2.1 / PKCE · **Auth:** user OAuth flow via `connectors/chatgpt/` · **Config:** `connectors/chatgpt/openapi.json`

### Setup

1. In ChatGPT: Explore GPTs → Create → Configure → Add Action → Import from URL or paste `openapi.json`
2. Set OAuth: Authorization URL, Token URL, Client ID, Scope from the BioMate OAuth server
3. Or for testing: set Authentication to API Key and use a BioMate API key directly

```
BIOMATE_API_URL = https://app.biomate.ai   (or dev-public.biomate.ai for testing)
OAuth client ID and secret from connectors/chatgpt/ config
```

---

### TC-GP-1 · OAuth flow — user connects BioMate account

**Input:** Click "Connect" in the GPT action settings → complete OAuth PKCE flow

**Expected:**
- Browser opens BioMate login/authorize page
- After login: redirect back to ChatGPT with access token
- GPT can now call BioMate tools on behalf of this user
- Token stored — subsequent calls don't require re-auth

- [ ] Pass  · [ ] Fail

---

### TC-GP-2 · ADMET screening via GPT prompt

**Input:**
```
Screen aspirin, ibuprofen, and naproxen for hERG and CYP3A4 inhibition using BioMate.
Flag any compound with hERG IC50 < 1 µM.
```

**Expected:**
- GPT calls `biomate_session` or `run_workflow` via OpenAPI action
- Returns workflow card with run ID and status
- After completion: per-compound ADMET values displayed
- "View in BioMate" deep link included

- [ ] Pass  · [ ] Fail

---

### TC-GP-3 · Literature search via GPT

**Input:**
```
Search BioMate for recent papers on PD-L1 checkpoint inhibitor resistance mechanisms in NSCLC.
```

**Expected:**
- `search_literature` called via OpenAPI action
- Returns ≥ 10 papers with titles, authors, DOIs
- Papers are real (spot-check 2–3 DOIs via PubMed)
- No hallucinated citations

- [ ] Pass  · [ ] Fail

---

### TC-GP-4 · Database lookup — compound target profile

**Input:**
```
Look up osimertinib in BioMate's biological databases. I want its known targets and clinical trial status.
```

**Expected:**
- `query_database` called with `entity_type="compound"`
- Returns ChEMBL bioactivity data (EGFR T790M IC50)
- Clinical trials from OpenFDA / ClinicalTrials.gov if available
- No fabricated assay values

- [ ] Pass  · [ ] Fail

---

### TC-GP-5 · Run status + results retrieval

**Input:**
```
Check the status of my most recent BioMate run and show me the output files.
```

**Expected:**
- `list_runs(limit=1)` → most recent run ID
- `get_run_status` → current status
- If completed: `get_run_results` → output file list with download URLs
- GPT presents results in readable format, not raw JSON

- [ ] Pass  · [ ] Fail

---

## Test execution order

```
TC-FE-2   (unbound gate — must run before TC-FE-1)
TC-FE-1   (bind)
TC-CS-1   (auth gate — no token → 401)
TC-CS-2   (tool count — verify 11 tools)
TC-GP-1   (OAuth flow — must complete before other GP tests)
TC-CC-1 → TC-CC-2 → TC-CC-3 → TC-CC-4 → TC-CC-5
TC-CS-3 → TC-CS-4 → TC-CS-5
TC-CX-1 → TC-CX-2 → TC-CX-3 → TC-CX-4 (use run_id from CX-2) → TC-CX-5
TC-GP-2 → TC-GP-3 → TC-GP-4 → TC-GP-5
TC-SL-1 → TC-SL-2 → TC-SL-3 → TC-SL-4 → TC-SL-5
TC-FE-3 → TC-FE-4 → TC-FE-5
```
