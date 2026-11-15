# Galaxy capabilities BioMate can leverage (broader discovery)

**Date:** 2026-11-13  
**Trigger:** User — “Galaxy obviously has many powerful abilities; what else can we leverage?”  
**Scope:** Read-only traversal of BioMate’s Galaxy wiring vs Galaxy’s full API surface. **Document only** — no feature implementation in this pass.  
**Related (do not conflict):** `docs/20261113_FOLDER_AS_INPUT_GALAXY_LEVERAGE.md` covers folder/HDCA in depth; another agent may be shipping **folder → all-files** (`folder-as-input.ts` / `attachFolder`). This doc stays at the broader capability map and points at that work instead of re-planning it.

---

## Executive takeaway

BioMate already **owns** Galaxy as an execution + AI substrate (Nextflow executor, AI assistant, perception, billing internals, user provisioning, histories for staging). The big unused value is not “more Galaxy tools in the toolbox” — it is **finishing half-wired primitives** that match BioMate’s product plane (project_files + S3 + Nextflow/Batch), and **consciously skipping** Galaxy features that fight that plane (native GA HDCA binding for nf-core, Galaxy Interactive Tools vs `run_code`, Galaxy quotas vs Stripe/internal quota).

---

## 1. Galaxy API surface BioMate already wires

### 1.1 `GalaxyAPIProxy` (`frontend/server/galaxy-api-proxy.ts`)

| Area | Methods / capability |
|------|----------------------|
| Auth / tenancy | `provisionGalaxyUser`, `forUser` + key recovery |
| Tools | `searchTools`, `getToolCategories`, `getToolById`, `getToolSchema`, install / installed list |
| Datasets (BioMNI catalog) | search / by category / by id / by schema / compatible |
| Workflows (Galaxy + BioMate) | `getWorkflow`, `createWorkflow`, `invokeWorkflow`, `getInvocation`, `cancelInvocation`, `importWorkflow`, `getWorkflowInputs`, `generateWorkflow`, multi-agent generate |
| Nextflow / autofix | `getNextflowStatus`, autofix3 run / sessions / status |
| Jobs | get / stdout / stderr / pause / resume / outputs |
| Histories | create, list, contents, upload file / URL, download, metadata |
| Tool jobs | `submitToolJob` |
| Research / bench | `queryResearch`, `queryBenchmark` |
| Reports | `getWorkflowReport`, `configureWorkflowReport` |
| Collections | `createDatasetCollection`, `createPairedCollection`, `autoPairDatasets` |
| Deferred datasets | create + materialize |
| Interactive tools | launch, active sessions, availability cache |
| Subworkflows | `extractSubworkflow` |
| LCMS | `callLCMSAgent` |

### 1.2 Node routes that proxy or reshape Galaxy

**`/api/galaxy/*` — classic Galaxy surface**

- Tools: version, search, categories, by id, schema, installed list  
- Datasets: search, category, get, resolve  
- Histories: list (Galaxy + BioMate runs as virtual histories), history datasets  
- Workflows: create, invoke, get invocation  
- Jobs: get, stdout/stderr, pause/resume  
- Autofix3 + SSE for Galaxy invocations  

**BioMate product routes that call Galaxy under the hood**

| Product route family | Galaxy / backend behind it |
|----------------------|----------------------------|
| `/api/workflows/execute`, runs/*, status, outputs, cancel, pause/resume, rerun, save-to-project | `nextflow_executor` + invocations + chain |
| `/api/workflows/search`, spec, by-domain, personal upload (.nf/.ga), chain, preflight, estimate_cost, explain_error, parse_error | AI + Nextflow + cost |
| `/api/invocations/*` (outputs, methods-report, QC events, software, autofix) | invocations + report paths |
| `/api/datasets/upload`, import-url, download, validate, session; lineage/consumers/versions/ro-crate | histories + `datasets_object.py` |
| `/api/collections*`, `/api/datasets/deferred`, materialize | collections + deferred HDAs |
| `/api/interactive/*`, project `…/open-in` | Interactive Tools / entry_points |
| `/api/data/sources`, `/browse`, `/fetch`; `/api/s3/browse` | `remote_files` + `nextflow/fetch_public_data` + S3 browse |
| `/api/perception/profile`, project folders/profile | `perception.py` + `folder_profile.py` (Galaxy datatypes when available) |
| `/api/code/run` (`run_code`) | BioMate sandbox (not Galaxy GIT) — stages Galaxy/session datasets |
| Billing internals, LLM cost, job completed | Galaxy billing API modules |
| User Galaxy API key provisioning | `provisionGalaxyUser` |

### 1.3 Galaxy backend API modules present in-tree

Under `backend/lib/galaxy/webapps/galaxy/api/` BioMate ships (or vendors) the full Galaxy webapp API set **plus** BioMate extensions, including among others:

**Heavily used / BioMate-extended:** `nextflow_executor`, `ai_assistant`, `workflows`, `workflow_chain`, `chat`, `perception`, `datasets_object`, `billing*`, `jobs`, `histories`, `history_contents`, `datasets`, `tools`, `uploads`, `remote_files`, `file_sources`, `autofix3`, `models_*`, `drug_discovery`, `cryosparc_*`, `folder_contents` / `folders`, `credentials_api`, etc.

**Present but largely unused by BioMate product UI:** `libraries` / `library_*`, `visualizations`, `pages` / `page_revisions`, `forms`, `quotas`, `roles` / `groups` / `group_*`, `toolshed` / `tool_shed_repositories`, `trs_search` / `trs_consumer`, `tool_data`, `object_store`, `display_applications`, `drs`, `tours`, `storage_cleaner`, `short_term_storage`, Galaxy-native `provenance` (HDA/LDDA job chain — distinct from BioMate `datasets_object` lineage), `annotations` / `item_tags` / `tags` (mostly health probes), `extended_metadata`, `genomes` (igenomes resolution exists on execute path; no user-facing genomes browser), `metrics` (job metrics API), `dataset_collections` (server exists; BioMate UI does not drive it — see folder doc).

---

## 2. Capability matrix — underused / unused vs BioMate surfaces

Legend: **Wired** = proxy/route exists and is called in a real product path. **Half** = server wired, UI/engine missing or gated off. **Unused** = Galaxy module exists, BioMate product ignores it. **Conflict** = feature fights Nextflow/Batch / sandbox architecture.

| Galaxy capability | Status in BioMate | Chat | Data Hub | Models | Workflows | CRO |
|-------------------|-------------------|------|----------|--------|-----------|-----|
| Histories + upload/staging | **Wired** (session history, IT staging) | attach/upload | via project_files primarily | sandbox staging | execute staging | — |
| Nextflow / Batch via Galaxy | **Wired** (core) | cards + SSE | save-to-project | train via Nextflow | panel + Runs | attach results |
| Collections / HDCA | **Half** (POST `/api/collections*`; no UI; Nextflow rejects HDCA inputs) | tooltip only | folder≠HDCA | no | engine gate | — |
| Folder profile + samplesheet | **Wired** (profile + download); **Use→attach** evolving separately | attachFolder WIP | FolderProfileView | folder pick gap | nf samplesheet | — |
| Remote files (FTP/HTTP plugins) | **Half** (`/api/data/*` + connectors); UI connectors uneven | connectors | import-url / connectors | — | fetch→S3 | — |
| Deferred URL datasets | **Half** (API + quota check); little UX | rare | — | — | — | — |
| Interactive Tools (Jupyter/RStudio/cellxgene) | **Half / Conflict** — routes + Open-in exist; `INTERACTIVE_TOOLS_ENABLED` off on typical deploys (no docker socket); UI buttons intentionally hidden | — | Open-in disabled | — | AfterRun IT row gated | — |
| `run_code` sandbox | **Wired** (deliberate GIT substitute) | primary ad-hoc compute | generated files | Models sandbox | — | — |
| Native Galaxy workflows (`.ga` invoke) | **Closed on import** (2026-11-15) — UI + `upload-file` reject `.ga`; proxy invoke path still unused; Nextflow-only personal import | rare | — | — | library import (nf/yml only) | — |
| Workflow reports (Galaxy invocation report) | **Half** — proxy `getWorkflowReport`; product uses BioMate methods-report / findings / AfterRun | — | — | — | Findings / methods-report | IND narrative separate |
| Lineage / provenance | **Wired (BioMate)** via `datasets_object`; Galaxy HDA provenance **Unused** | — | DatasetObject tabs | model lineage | reproducibility endpoints | compliance package |
| Visualizations (Galaxy viz plugins) | **Unused** | markdown/plots via run_code | file preview | — | step preview | — |
| Display applications (IGV, etc.) | **Unused** | — | preview stubs | — | — | — |
| Data Libraries (LDDA trees) | **Unused** | — | project tree ≠ libraries | — | — | institutional share gap |
| Tags / annotations | **Unused** (tags hit in health checks) | — | project notes separate | — | — | — |
| Forms / Pages | **Unused** | — | — | — | — | — |
| Tool Shed / TRS / Dockstore | **Unused** (install APIs in proxy; catalog is `galaxy_ai_tools.db`) | — | — | — | personal .nf/.yml upload | — |
| Data managers / tool_data tables | **Unused** as admin UI; igenomes auto-resolve on execute | — | — | — | genome params | — |
| Job metrics (Galaxy) | **Unused**; BioMate has cost estimate + billing Redis | — | — | — | estimate_cost, billing | — |
| Quotas (Galaxy disk) | **Conflict / Unused** — BioMate uses Stripe + internal quota | — | — | — | quota_enforcer | — |
| Roles / groups (Galaxy) | **Conflict / Unused** — BioMate Team plan + project members | — | project share | — | — | CRO campaigns |
| Object store plugins | **Half** — S3 is the plane; Galaxy object_store API not productized | — | S3 upload | — | Batch work dir | — |
| Rule-based uploader | **Unused** | — | folder upload expands files | — | — | — |
| Sample sheets (Galaxy) | **Replaced** by folder_profile nf-core CSV | — | download samplesheet | — | `--input` | — |
| Workflow sharing / published GA | **Unused**; BioMate has Workflows library + personal uploads + deep links | seed chat | — | — | library | — |
| API keys | **Wired** — BioMate connector keys + per-user Galaxy keys | MCP/connectors | — | — | headless | — |
| Subworkflow extract | **Half** — POST extract-subworkflow; no UX | — | — | — | — | — |
| Autofix / deep diagnose | **Wired** for invocations | error paths | — | — | panel | — |

---

## 3. Architecture conflicts (do not “leverage” blindly)

1. **HDCA ↔ Nextflow** — Galaxy collections are first-class for Galaxy tools / `data_collection_input`. BioMate’s default `executionEngine === 'nextflow'` path uses params + S3; `inputsUnsupportedForNextflow` refuses Galaxy-style HDCA bindings. Leverage = materialize samplesheet/S3 list **or** Galaxy-engine-only HDCA — not pass HDCA ids into Batch.

2. **Interactive Tools ↔ sandbox** — Galaxy ITs need a container runtime (docker/k8s IT destination). BioMate deliberately uses **`run_code`** (gVisor/sandbox) for ad-hoc Python/R. Enabling GIT means infra work + security review; until then, keep buttons gated and invest in sandbox + preview, not half-enabled IT.

3. **Galaxy quotas / roles ↔ BioMate tenancy** — Disk quotas, Galaxy groups, and library ACLs duplicate Stripe tiers, project membership, and S3 keys. Do not surface Galaxy admin quota/roles as the product RBAC.

4. **Native GA vs indexed Nextflow catalog** — BioMate’s strength is 4k+ indexed Nextflow/Bioconductor workflows on Batch. Rebuilding the classic Galaxy “tool form + history” UX would fork the product. Keep Galaxy-tool invoke for edge cases; keep catalog + Nextflow as the default.

5. **Galaxy visualizations / display apps ↔ BioMate previews** — Step file preview + perception already cover common formats. Embedding Galaxy viz plugins adds iframe/host coupling without improving Batch output UX.

6. **Tool Shed live install ↔ curated DB** — Dynamic Tool Shed installs are ops-heavy and conflict with Batch container images. Prefer catalog indexing + container pins over user-facing Shed install.

---

## 4. Top leverage opportunities (ranked)

Ranking ≈ **user value × feasibility** under Nextflow/Batch. Scores are relative (H/M/L).

### 1. Public remote data → project file in one click — **H × H**

**Galaxy offers:** `remote_files` plugins (EBI/NCBI/Ensembl/UCSC FTP, HTTP) + fetch.  
**BioMate today:** `/api/data/sources|browse|fetch` wired; Connectors UI exists but “browse FTP → land in project_files → bind param” is still fragmented vs simple URL import.  
**Smallest step:** Data Hub “Import from public source” that calls browse → fetch → `project_files` row + optional chat attach (reuse existing fetch→S3).

### 2. Deferred / large URL import with explicit materialize — **H × H**

**Galaxy offers:** deferred datasets (register URL without immediate download) + materialize.  
**BioMate today:** `POST /api/datasets/deferred` + materialize routes exist; UX barely uses them (users hit sync import or fail on huge files).  
**Smallest step:** On import-url over size threshold, create deferred ref in Data Hub with “Download when needed” / auto-materialize on Confirm & Run.

### 3. Finish samplesheet-as-workflow-input (complement folder→all-files) — **H × H**

**Galaxy offers:** pairing semantics (already reused in `folder_profile`) + collections conceptually.  
**BioMate today:** samplesheet **download** works; Analysis “one folder input” for nf-core is still incomplete; parallel work may ship folder→**all files** (`attachFolder`) — that helps Models/bulk attach but is **not** the nf-core `--input` CSV story.  
**Smallest step:** Keep out of the other agent’s attachFolder path; add **Use → persist samplesheet project_file → attach** for FASTQ folders only (see folder leverage doc item A). Do not create HDCAs for Nextflow.

### 4. Job / run cost + metrics surfacing (Galaxy metrics + BioMate billing) — **H × M**

**Galaxy offers:** per-job metrics API; BioMate already has `estimate_cost`, Lago/Redis billing, `/api/billing/*`.  
**BioMate today:** pre-run estimate badge; post-run cost in billing, not always inline on the workflow panel / Runs list.  
**Smallest step:** After run completion, show estimated vs actual vCPU-hours from billing ledger on the Runs row (no Galaxy metrics required); optionally later map Batch CloudWatch → same strip.

### 5. Methods / software / citations pack (already half there) — **H × H**

**Galaxy / BioMate offers:** methods-report, software list, workflow citations endpoints on invocations.  
**BioMate today:** download buttons exist in places; CRO / IND still assemble packages ad hoc.  
**Smallest step:** One “Reproducibility pack” zip on completed runs: methods-report + software + citations + RO-Crate JSON (endpoints already exist).

### 6. Datatype / perception → param gating — **M × H**

**Galaxy offers:** rich datatype registry + sniff + converters.  
**BioMate today:** `perception` profiles files; param strip still weak at refusing wrong types before Batch spend.  
**Smallest step:** On Confirm & Run, if perception `format`/`kind` conflicts with param datatype hints, block with Fix now (reuse perception; don’t rebuild Galaxy datatype UI).

### 7. Galaxy-engine collections only for non-Nextflow tools — **M × M** *(Conflict if misapplied)*

**Galaxy offers:** HDCA list / list:paired + tool `data_collection_input`.  
**BioMate today:** collections API wired; UI none; Nextflow rejects.  
**Smallest step:** UI “Create collection” only when `executionEngine === 'galaxy'`; never bind HDCA into Nextflow execute. (Defer if Galaxy-engine share of runs is tiny.)

### 8. Subworkflow / chain UX polish — **M × M**

**Galaxy offers:** subworkflow extract; BioMate has workflow_chain + extract-subworkflow API.  
**BioMate today:** chain used for GEO→DE style gates; extract has no UI.  
**Smallest step:** In workflow panel, “Save these steps as reusable chain” → call extract or record-chain — only if chain runs are already common for the user cohort.

### 9. Interactive Tools — enable or drop the illusion — **M × L** *(Conflict)*

**Galaxy offers:** Jupyter / RStudio / cellxgene entry points.  
**BioMate today:** full client wiring; runtime gated off; founder disabled Open-in.  
**Smallest step:** Either provision IT destination + set `INTERACTIVE_TOOLS_ENABLED` on one env, **or** remove AfterRun IT chrome and document `run_code` + download as the supported path. Do not leave dead buttons.

### 10. Display / viz for BAM/VCF/h5ad without GIT — **M × M**

**Galaxy offers:** display applications + viz plugins.  
**BioMate today:** step preview for tables/images/text; binary genomics formats are download-ish.  
**Smallest step:** Prefer lightweight BioMate viewers (e.g. IGV.js for small BAM/VCF slices, cellxgene-style only if IT enabled) over embedding Galaxy viz iframes.

### 11. Personal `.ga` → runnable Nextflow or honest “Galaxy-only” — **Done (import closed)**

**Galaxy offers:** import `.ga`, invoke on Galaxy jobs.  
**BioMate (2026-11-15):** Import Workflow UI + `POST /api/workflows/upload-file` reject `.ga` (415) — Nextflow-only (`.nf` / `.yml` / `.yaml`). No silent conversion; no misleading import path. Full Galaxy-engine invoke UX remains out of scope unless product prioritizes it.

### 12. Data Libraries for institutional reference sets — **L × L**

**Galaxy offers:** shared LDDA folder trees + roles.  
**BioMate today:** project_files + S3; Team sharing is project-scoped.  
**Smallest step:** Skip unless an on-prem customer asks; map to read-only shared project or S3 prefix instead of Galaxy libraries.

---

## 5. Explicit non-goals (this pass)

- Do not implement folder→all-files here (parallel agent / `folder-as-input.ts`).  
- Do not wire HDCA into Nextflow.  
- Do not enable Interactive Tools without runtime.  
- Do not sync to dev or ship product code from this discovery.

---

## 6. Suggested next implementation order (when approved)

1. Remote public source → project_files (opportunity 1)  
2. Deferred large URL import UX (2)  
3. FASTQ folder → samplesheet attach (3) — coordinate with folder→all-files so UX labels differ (“All files” vs “Samplesheet for RNA-seq”)  
4. Reproducibility pack zip (5)  
5. Perception-based Confirm & Run gate (6)  
6. Runs cost strip (4)  

---

## 7. Key file pointers

| Concern | Path |
|---------|------|
| Proxy surface | `frontend/server/galaxy-api-proxy.ts` |
| Route wiring | `frontend/server/routes.ts` (`/api/galaxy/*`, collections, interactive, data/*) |
| Nextflow executor | `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` |
| Lineage (BioMate) | `backend/lib/galaxy/webapps/galaxy/api/datasets_object.py` |
| Folder / samplesheet | `backend/lib/galaxy/ai/folder_profile.py`, `docs/20261113_FOLDER_AS_INPUT_GALAXY_LEVERAGE.md` |
| Folder→all-files (parallel) | `frontend/client/src/lib/folder-as-input.ts` |
| HDCA vs Nextflow gate | `workflow-input-gate.ts` (`inputsUnsupportedForNextflow`) |
| IT availability gate | `routes.ts` `GET /api/interactive/available` + `INTERACTIVE_TOOLS_ENABLED` |
| Workflow catalog | `backend/database/galaxy_ai_tools.db` |

---

---

## 8. Follow-up: remainder beyond this top list

See **`docs/20261113_GALAXY_WHAT_ELSE.md`** for Galaxy capabilities that are real, not fully productized, and **not** covered by the near-term top 5 (remote fetch, deferred URL, FASTQ samplesheet, reproducibility zip, datatype Confirm&Run gate) — plus an explicit skip list (Pulsar/CVMFS/TPV, OIDC, libraries/quotas/roles, IT, Shed, etc.).

---

**Document only.** Commit this file; no sync; no feature code in this pass.
