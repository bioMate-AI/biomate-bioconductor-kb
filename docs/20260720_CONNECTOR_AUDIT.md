# BioMate Connector Audit — 2026-07-20

Tested against: `https://dev-public.biomate.ai`
Fixture account: `lifeifei163361@163.com`
Tester: Claude Code (automated curl + python3)

---

## Summary

| Component | Status | Notes |
|---|---|---|
| Auth (login) | ✅ Works | JWT returned correctly |
| Workflow routing (8 use cases) | ✅ Works | See routing table below |
| Database query (UniProt) | ✅ Works | `/api/databases/query` |
| Literature search | ✅ Works | `/api/literature/search` — 10 papers for CD40LG |
| Accession resolve | ✅ Works | `/api/accession/resolve` — GSE142256 → Geo Data Connector |
| App links (account/connectors, billing, api-keys) | ✅ All 200 | Verified with curl |
| OAuth endpoints (authorize, token) | ✅ 200 | `dev-public.biomate.ai/oauth/...` |
| GitHub repo | ✅ 200 | `github.com/bioMate-AI/biomate-connector` |
| ChatGPT OpenAPI schema | ✅ GitHub raw | `raw.githubusercontent.com/...` (updated) |
| ChatGPT `/tools/*` adapter | ❌ Not deployed | `chatgpt_adapter.py` not running on dev |
| `@biomate/connect` npm package | ❌ Not published | 404 from registry.npmjs.org |
| `@biomate/mcp-server` npm package | ❌ Not published | 404 from registry.npmjs.org |
| `dev-public.biomate.ai/mcp/openapi.json` | ❌ Was 500 | Removed from docs; replaced with GitHub raw URL |

---

## Workflow Routing — 8 Use Cases

All tested via `POST /api/ai_assistant/generate_workflow` with `request_text`.

| Use Case | Routed Workflow | Confidence |
|---|---|---|
| RNA-seq DESeq2 GRCh38 paired-end | `nf-core/rnaseq` | 65 |
| ADMET hERG CYP3A4 oral bioavailability | `Predict ADMET Properties (AI)` | 67 |
| scRNA-seq 10x Chromium UMAP Seurat | `nf-core/scrnaseq` | 83 |
| PBPK oral dose 70 kg adult 8-compartment | `pbpk_simulation` | 67 |
| WGS variant calling GATK HaplotypeCaller germline | `Wgs Germline Gatk` | 78 |
| MOFA2 multi-omics RNA-seq + proteomics | `rnaseq_proteomics_multiomics_integration` | 73 |
| CryoEM CryoSPARC SPA C2 symmetry | `CryoSPARC Standard Single-Particle Analysis` | 97 |
| GWAS eQTL colocalization autoimmune | `gwas_scrna_eqtl_target_chain` | 43 |

All 8 returned `success: true` with generated parameters.

---

## Tool API Paths (actual vs. OpenAPI schema)

The OpenAPI schema for ChatGPT defines paths as `/tools/<name>`. These routes
do **not** exist in the Node backend — they belong to `chatgpt_adapter.py`,
which must be run as a separate process. The actual backend routes are:

| Tool | Actual backend route |
|---|---|
| `search_workflow` / `generate_workflow` | `POST /api/ai_assistant/generate_workflow` |
| `query_database` | `POST /api/databases/query` or `/api/databases/federated` |
| `search_literature` | `POST /api/literature/search` |
| `resolve_accession` | `POST /api/accession/resolve` |
| Auth | `POST /api/auth/login` |

---

## Accession Resolve — GSE142256

```json
{
  "accession": "GSE142256",
  "accession_type": "GEO_series",
  "archive": "GEO",
  "workflow_id": 10672,
  "workflow_name": "Geo Data Connector",
  "nextflow_path": "nextflow_nfcore/subworkflows/genomics/geo_data_connector/main.nf",
  "description": "Downloads GEO series matrix + clinical metadata via GEOquery; emits channels ready for DESeq2/edgeR.",
  "ready_to_run": true,
  "next_step": "Call run_workflow with workflow_id=10672 and params={\"accession\":\"GSE142256\"}"
}
```

---

## Fixes Applied This Session

### connectors.html (marketing website)
1. ChatGPT OpenAPI schema URL: `dev-public.biomate.ai/connectors/chatgpt/openapi.json` (was returning SPA HTML) → `raw.githubusercontent.com/bioMate-AI/biomate-connector/main/connectors/chatgpt/openapi.json`
2. ChatGPT OAuth URLs: `biomate.ai/oauth/...` and `api.biomate.ai/oauth/...` → `dev-public.biomate.ai/oauth/...`
3. Overview prose: `api.biomate.ai` references → `dev-public.biomate.ai`
4. Removed all references to `dev-public.biomate.ai/mcp` (was returning 500)
5. Added "developer preview" callout on ChatGPT section noting `/tools/*` not yet deployed
6. Added early-access notice on `@biomate/connect` CLI (npm 404)
7. JSON-LD `downloadUrl`: `npmjs.com/package/@biomate/mcp-server` → GitHub repo URL
8. Added sidebar "Use cases" nav entry
9. Added 5 end-to-end use case flows with real information flow details

### biomate-connector repo
1. `connectors/chatgpt/openapi.json` server URL: `api.biomate.ai` → `dev-public.biomate.ai`
2. `connectors/chatgpt/openapi.json` OAuth URLs: `biomate.ai/oauth/...` → `dev-public.biomate.ai/oauth/...`
3. `connectors/feishu/.env.example` `BIOMATE_API_URL`: `test.stage-public.biomate.ai` → `dev-public.biomate.ai`
4. `connectors/feishu/.env.example` `BIOMATE_DEEP_LINK_BASE`: same fix
5. `connectors/claude-code/README.md`: `~/.claude.json` → `~/.mcp.json`

---

## Open Issues (not fixed — require server-side work)

1. **ChatGPT adapter not deployed** — `chatgpt_adapter.py` needs to be deployed as a separate service at `dev-public.biomate.ai` and `/tools/*` routes added to the Node reverse proxy. Until then, ChatGPT integration requires self-hosting.
2. **npm packages not published** — `@biomate/connect` and `@biomate/mcp-server` return 404 from npm. The installer code is in the repo at `connectors/installer/` but has not been published. Run `npm publish` from that directory after `npm run build`.
3. **Slack/Feishu** — Integration pages at `/integrations/slack` and `/integrations/feishu` return 200 (the React SPA handles these routes) but the actual Slack/Feishu bot flows require self-hosting per the connector READMEs.
