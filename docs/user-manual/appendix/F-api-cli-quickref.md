# Appendix F — API / Connector / CLI Quick Reference

BioMate can be driven programmatically. Two surfaces are documented here:

1. **Connector tools** (MCP / Open Claw / ChatGPT Action / Claude Skill / Slack / WeChat) — the canonical
   set of tools an agent or host calls. **Single source of truth:**
   `backend/lib/mcp/tools_manifest.py` (`TOOL_SCHEMAS`). Drift from this file is a bug, guarded by
   `tests/test_tools_manifest_drift.py`.
2. **REST endpoints** referenced by the module/domain chapters — the HTTP routes the web UI (and the
   connector proxy) call. Each backend path below is the `backend_path` declared for the tool in the
   manifest, or the route cited in the coverage ledger.

> **Honesty note:** the manifest description strings say "2,455 indexed workflows across 34 domains."
> The **live catalog is 4,200 workflows / 42 domains / 70 chains** (Appendix E). Trust the live count,
> not the manifest blurb.

---

## 1. Connector tools (from `tools_manifest.py`)

Tools are grouped into three tiers. `streams` marks tools that emit MCP `notifications/progress` (live
phase/step/QC events). "Required" lists the required input fields.

### Tier 1 — streaming agentic

| Tool | What it does | Required | Streams | Backend path |
|---|---|---|---|---|
| `biomate_session` | Run a complete session from a natural-language goal (BioMate picks workflow, fills params, runs on Batch, handles QC/auto-loop, returns findings + panel link + report URL) | `goal` | ✔ | `POST /api/open-claw/stream` |

### Tier 2 — workflow primitives

| Tool | What it does | Required | Streams | Backend path |
|---|---|---|---|---|
| `search_workflow` | Search the workflow catalog by NL; ranked cards (id, name, domain, cost) | `query` | | `POST /api/workflows/search` |
| `get_workflow_spec` | Full spec: params (types/allowed values), default QC profile + thresholds, expected inputs, cost/runtime, license | `workflow_id` | | `GET /api/workflows/spec` |
| `run_workflow` | Execute a specific workflow on Batch with explicit params; returns `run_id` | `workflow_id` | ✔ | `POST /api/workflows/execute` |
| `get_run` | Everything about a run in one call: status, per-phase/step progress, outputs (download URLs), findings, QC results, auto-loop remediations | `run_id` | | `GET /api/workflows/runs/{run_id}` |
| `cancel_run` | Cancel a running/queued run | `run_id` | | `POST /api/workflows/runs/{run_id}/cancel` |
| `list_runs` | List recent runs (filter by status/experiment) | — | | `GET /api/workflows/runs` |
| `watch_run` | Stream live progress for an existing run, then return full results | `run_id` | ✔ | `GET /api/workflows/runs/{run_id}` |

### Tier 3 — outputs, analysis, data, reporting, memory

| Tool | What it does | Required | Backend path |
|---|---|---|---|
| `preview_file` | Server-side preview of an output file (FASTA/VCF/CSV/TSV/image/PDF) → markdown + optional thumbnail | `s3_key` | `POST /api/files/preview` |
| `export_report` | Render a publication-ready report (pdf/markdown/docx) — methods, QC audit, findings, figures | `run_id` | `GET /api/workflows/runs/{run_id}/findings/report` |
| `analyze_results` | AI interpretation of a completed run (findings, quality, next steps) | `run_id` | `POST /api/workflows/runs/{run_id}/ai/analyze` |
| `explain_error` | Diagnose a failed run (root cause + fix) | `run_id` | `POST /api/workflows/explain_error` |
| `query_database` | Query a bio/chem DB by accession/name (uniprot, pdb, pdbe, alphafold, interpro, string, ncbi_gene, ensembl, dbsnp, clinvar, gnomad, kegg, reactome, go, hpo, chebi, chembl, pubchem, bindingdb, pharos) | `database`, `query` | `POST /api/databases/query` |
| `resolve_accession` | Identify a public accession (GEO/SRA/ENA/DDBJ) → best fetch workflow + pre-filled params | `accession` | `POST /api/accession/resolve` |
| `browse_data` | List files/dirs at a repository path or S3 prefix (ebi_ftp, ncbi_ftp, ensembl_ftp, ucsc_downloads, http_public, biomate_workspace, user_s3) | `source_id` | `GET /api/data/browse` |
| `fetch_public_data` | Download a public-repo file into BioMate's S3 workspace → presigned URL + S3 URI | `source_id` | `POST /api/data/fetch` |
| `search_literature` | Iterative depth-loop search across PubMed / EuropePMC / Semantic Scholar / OpenAlex | `query` | `POST /api/literature/search` |
| `recall_memory` | Retrieve prior context (past runs, procedures, findings, param prefs) | `query` | `GET /api/memory/relevant` |
| `upload_file` | Get a one-shot signed S3 PUT URL so the host uploads directly (mandatory for files > 5 MB) | `filename` | `POST /api/uploads/signed_url` |

> **Which tool to reach for:** if you have a natural-language goal, use `biomate_session` (it routes,
> fills params, runs, and handles QC for you). Use `search_workflow` → `get_workflow_spec` →
> `run_workflow` only when you want explicit workflow/parameter control. If the user hands you an
> accession, call `resolve_accession` first — but note the resolvable-vs-validation-only limits in
> Appendix E (only GEO/SRA/ENA/DDBJ auto-fetch; PDB/EMDB/PRIDE etc. do **not**).

### Manifest exporters (for integrators)

`tools_manifest.py` regenerates surface-specific schemas from the one source: `to_mcp()` (MCP
`tools/list`, `inputSchema`), `to_anthropic()` (`input_schema`), `to_openai()` (function-calling),
`to_openapi()` (OpenAPI 3.1 at `connectors/chatgpt/openapi.json`; `POST /tools/{tool_name}`; OAuth 2.0),
and `to_skill_catalog()` (Claude Skill markdown). Run `python -m backend.lib.mcp.tools_manifest` to
rebuild `tools_manifest.json`.

Auth on the OpenAPI surface is OAuth 2.0 (`/oauth/authorize`, `/oauth/token`) with scopes `runs:read`,
`runs:write`, `workflows:search`, `memory:read`, `memory:write`, `billing:read`. Common responses:
`401` reauthorize, `402` quota/billing gate, `429` rate-limited (respect `Retry-After`).

---

## 2. Key REST endpoints (from the chapters / coverage ledger)

These are the web-UI routes cited in the module and domain chapters. Paths are relative to the app host;
the UI proxies through the Node server (port 5000) to the Galaxy backend.

### Runs & workflows

| Endpoint | Purpose | Chapter |
|---|---|---|
| `POST /api/workflows/search` | Workflow catalog search / routing | Data II.1 |
| `GET /api/workflows/spec` | Full workflow spec | I.6 |
| `POST /api/workflows/execute` | Confirm & Run (AWS Batch) | I.6 |
| `GET /api/workflows/:invocationId/events` | Live status SSE (phase/step) | I.6 |
| `GET /api/workflows/runs/:id` | Run object (status, outputs, findings) | I.6 |
| `POST /api/workflows/runs/:id/rerun` | Re-run with edits | I.6 / I.9 |
| `GET /api/workflows/runs/:id/step-file` | Fetch a single step output file (feeds StepOutputPreview) | I.8 |
| `GET /api/nextflow/steps?nextflow_path=…` | Lazily fetch step definitions | Workflow DB |
| `POST /api/invocations/:id/autoloop-suggestions` | Auto-loop remediation suggestions (ADMET) | Drug discovery → IND |

### Data, accession & perception

| Endpoint | Purpose | Chapter |
|---|---|---|
| `POST /api/accession/resolve` | Resolve a public accession to a fetch workflow (**GEO/SRA/ENA/DDBJ only**; others 422 — Appendix E) | Data II.2 |
| `POST /api/perception/profile` | Compute a dataset's quality profile (quality dot) | I.5 |
| `GET /api/interactive/available` | Whether interactive tools are provisioned (returns `available:false` on dev — honesty gate) | I.8 / Appendix D |

### Reports & reproducibility

| Endpoint | Purpose | Chapter |
|---|---|---|
| `GET /api/workflows/runs/:id/findings/report` | Render the report (via `export_report`) | I.9 |
| `POST …/report/versions` | Save a new report version (v0 immutable) | I.9 |
| Reproducibility record fetch with `?checksums=1` | Opt-in SHA-256 (off by default → "—") | I.9 / Appendix D |
| `/api/ind-report/projects/:id/document.docx` · `.md` | IND DOCX / Markdown export | Drug discovery → IND |
| `/api/ind-report/projects/:id/attachments` | Wet-lab attachment upload (measured overrides predicted) | Drug discovery → IND |

### Search / literature

| Endpoint | Purpose | Chapter |
|---|---|---|
| `POST /api/literature/search` | Literature search (PubMed / arXiv / Semantic Scholar; +PMC/EuropePMC full text) | I.3 / Data II.3 |
| `POST /api/databases/query` | Live DB lookup by accession/name | Data II.4 |

### Projects, memory, billing

| Endpoint | Purpose | Chapter |
|---|---|---|
| `GET /api/projects` · `GET /api/projects/:id` | Projects (401 unauth, 404 cross-user — existence not leaked) | I.4 |
| `GET /api/memory/relevant` | Recall prior context (session summaries; not private notes) | Data II.5 |
| `GET /api/billing/usage` · `GET /api/billing/quota` | Usage breakdown + plan limits / % consumed | I.13 |

---
*Cross-references: Data II.1 (routing), Data II.2 (accession resolver), Module I.6 (running an analysis),
Module I.9 (reports). For endpoints/tools that exist but are unverified or not resolvable, see
Appendix E.*
