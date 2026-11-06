# Study-Replication Capability — Corrected Map, Credentials & Plan

**Date:** 2026-09-11 · **内部文档** · branch `integration/dev-test`
**Why this doc:** An earlier gap assessment labelled several study-replication capabilities "❌ can't". That was an **under-claim made without checking** — corrected here against a code/doc audit ([[20260911_REPLICATION_USER_JOURNEY_UX_AUDIT]] is the prior, partly-wrong version). Standard used: **a capable scientist operates the platform** (sets params, uploads data, runs their own code in Interactive Tools) — not "fully autonomous, untouched." So the bar is *"can a scientist reproduce the analyses **on** BioMate,"* not *"does it do everything by itself."*

## Honest correction up front
"Reproducing a study" is NOT "running one workflow." A workflow = one analysis (a figure-panel result), approximate at default params. BUT with Interactive Tools + `run_code` + chains + connectors + the user as operator, **most of the computational study is reproducible on BioMate** — far more than I first claimed. Only physical wet-lab actuation is out of scope.

---

## Corrected capability map (evidence-based)

3-way framing: **BUG** (blocks any user — must fix) · **USER-DRIVEN** (supported; scientist configures) · **OUT-OF-SCOPE** (not computational).

| # | Replication need | Verdict | How it's covered (evidence) | Residual / plan |
|---|---|---|---|---|
| 1 | Run the **paper's actual custom code** at exact params | ✅ architecturally (USER-DRIVEN) | **RStudio/Jupyter Interactive Tools** — real shell + R/Python + internet egress → clone the paper's GitHub, install pkgs, run their scripts (`routes.ts:14480/16589`, `job_conf.yml:58`, `docs/20260822_RSTUDIO..._WORKING.md`) | **Not yet demonstrated E2E** (verified: kernel/IDE/viz only). Dev-only (host docker socket); ephemeral. **Plan: demonstrate a real clone→install→run-author-script flow; productionize IT hosting.** |
| 2 | Ad-hoc analysis at **exact parameters** | ✅ (USER-DRIVEN) | **`run_code`** sandbox: R+Bioconductor+Python, arbitrary code (`galaxy-assistant.ts:79`, `code-runner.ts`, `Dockerfile.biotools`) | Offline (`--network=none`), ≤300s, 2GB/2CPU; **gated off when a workflow card is generated** (misclassification). **Plan: fix the gating heuristic so compute isn't suppressed; raise limits for heavier ad-hoc.** |
| 3 | **Data acquisition** beyond GEO | 🟡 partial | `resolve_accession`/`fetch_public_data`: **GEO+SRA+ENA+DDBJ** + EBI/NCBI/Ensembl/UCSC (`tools_manifest.py:517`) | **No controlled-access (dbGaP/EGA); no NGDC/GSA/CNCB/CNGB; no PRIDE.** **Plan below (§Credentials + fetchers).** |
| 3b | **Wet-lab instrument data ingestion** | ✅ | 10 real instrument connectors (BaseSpace/MinKNOW/EPU/LC-MS/FCS/Benchling/OpenTrons/SiLA2) → `POST /api/instruments/new-data` → auto workflow suggestion (`biomate-connector/lab_instruments/*`, `routes.ts:15330`) | Tests mock-based, no live-hardware round-trip proven in-repo. **Plan: one live-instrument round-trip.** |
| 4 | **Multi-analysis orchestration** (DE+ATAC+integration) | ✅ | **`workflow_chain`** engine, **70 curated chains**, sequential, automatic S3-URI handoff (`workflow_chain.py:432/222`, `artifact_contracts.py`, `galaxy_ai_tools.db:workflow_chains`) | Sequential only (no fan-out); no Redis cross-worker chain state; **full multi-workflow Batch completion unproven in-repo.** **Plan: prove one full chain end-to-end on Batch; add parallel + Redis state.** |
| 5 | **Interpretation / narrative** | ✅ IND only | IND/CTD `_llm_narrative` — genuinely interpretive §2.4/§2.6.1–2.6.3, frontier LLM + numeric-faithfulness guard + DOCX (`ind_assembly.py:692/573/3684`) | General **Findings tab + methods report are template/metadata (no LLM)**. **BUG:** §2.6.7 tox narrative keys absent from prompts dict → returns empty (`ind_assembly.py:3500` vs `:740-819`). **Plan: extend LLM interpretive narrative to the general Findings tab; fix §2.6.7.** |
| 6 | **Wet-lab / in-vivo execution** | ❌ (OUT-OF-SCOPE) | Design workflows + ingestion exist; **actuation is a deliberate stub** (`campaign_dbtl_bridge.py:19` "BUILD → stubbed wet-lab hop. No hardware"); only OpenTrons liquid-handling actuates | Correctly ❌ for computational replication. **Plan: integrate external programmatic wet-labs (ECL/Adaptyv) if/when the DBTL moat decision flips.** |

**Net:** of the six, **#2/#3b/#4/#5(IND) are real and wired; #1 is architecturally there but undemonstrated; #3 is partial; only #6 is a true ❌.** The under-claim was substantial.

---

## Credentials — how authenticated sources are handled (evidence)

Directly answers "for repos/data needing credentials, how do you handle it; existing MCPs?"

1. **Per-user credential Vault** — `credentials_api.py`: stores per-tool creds in **Galaxy Vault** (`UserVaultWrapper`, encrypted at rest, keyed `biomate/credentials/<tool_id>`); fallback to `user.preferences`; **master creds from env** for demo. API `GET/POST/DELETE /api/users/credentials`. Tied to a **license/requirement registry** (`GET /api/workflows/license-requirements`, `scan_nf_for_tool_ids`, `LICENSE_REGISTRY`) → BioMate knows which workflow needs which credential, prompts for it, injects at run time.
2. **Connector OAuth 2.1 + PKCE server** — `connectors/oauth/` (also `biomate-connector/oauth_server/`): HS256 JWT access (30-min) + HMAC-hashed rotating refresh, mandatory PKCE S256, RFC 7591 dynamic client reg, 8 scopes; per-user `bm_live_` keys Fernet-encrypted (`remote_mcp/credentials.py:31`). This is **inbound** (external MCP clients → BioMate). Gap: stateless JWTs have no server-side revocation list.
3. **Interactive Tools in-session** — user supplies their own token directly (git clone w/ PAT, `gh auth`, aws creds) in RStudio/Jupyter.

**Existing MCPs (24 tools, source of truth `biomate-connector/mcp/tools_manifest.py`):** the main `biomate_mcp_server.py` (search/run/get_run/query_database/resolve_accession/browse_data/fetch_public_data/preview_file/upload_file/export_report/analyze_results/recall_memory/search_literature/… + `list_instruments`/`get_instrument_status`/`run_instrument_protocol`); plus `chai1_mcp_server.py` (protein structure) and a PubMed MCP. Docs citing 17/19/22 tools are stale → **24**.

**The real credential gap:** the Vault *stores* a credential fine, but for **controlled-access research data** (dbGaP/EGA) and **non-Western archives** (NGDC/CNCB) there is **no fetcher that uses it** — `resolve_accession` only covers public GEO/SRA/ENA/DDBJ. So "authenticated repo" splits into: (a) private GitHub / cloud → **works today via IT in-session creds**; (b) controlled-access genomic archives → **needs a new credentialed fetcher wired to the Vault**.

---

## What we should do (plan, prioritized)

**P0 — prove what already exists (cheap, high-credibility).**
- Demonstrate the **IT clone-and-run-author-code** flow end-to-end (clone a paper's GitHub in RStudio, run their script → figure). Turns "architecturally yes" into "shown."
- Prove **one full multi-workflow chain** runs output→input to completion on Batch (e.g. `bulk_rnaseq_de_analysis`).
- Run the **P0 bulk-GEO auto-fetch** once the `local_series_matrix` fix deploys (already fixed) → confirm connector→DE end-to-end.

**P1 — close the real gaps.**
- **Credentialed data fetchers:** add dbGaP/EGA (controlled-access, via the Vault) + NGDC/CNCB/GSA (Chinese archives) + PRIDE (proteomics) to `resolve_accession`/`fetch_public_data`. This is the concrete "authenticated repo access" gap.
- **`run_code` gating:** stop suppressing compute when a workflow card is generated; raise the offline/limits envelope for heavier ad-hoc.
- **Findings narrative:** extend the IND-grade LLM interpretive narrative to the **general Findings tab** (today it's template-fill); **fix the §2.6.7 tox-narrative empty-string bug**.

**P2 — depth.**
- Chains: parallel/fan-out + Redis cross-worker state.
- IT: productionize hosting (remove the dev-only host-docker-socket dependency); persist sessions.
- One live-instrument round-trip (validate the ingestion connectors against real hardware).

**Out of scope (honest):** physical wet-lab/in-vivo actuation — integrate external programmatic labs (ECL/Adaptyv) only if the DBTL moat decision flips.

---

## Bottom line for the collaboration pitch
Honest and strong: *"A scientist can reproduce a paper's computational analyses on BioMate — standard pipelines (chained), their exact code and parameters in RStudio/Jupyter, ad-hoc R/Bioconductor via run_code, with credentialed access to their own private/cloud data — and get an interpretive regulatory-grade narrative for the drug-dev path. We do not run the wet-lab bench."* Avoid "replicates the entire study"; say "reproduces the computational study, scientist-in-the-loop."
