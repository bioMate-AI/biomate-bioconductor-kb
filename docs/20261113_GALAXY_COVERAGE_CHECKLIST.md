# Galaxy → BioMate coverage checklist

**Date:** 2026-11-13  
**Trigger:** User — “many are powerful to use. Check our current coverage and make a list.”  
**Scope:** Document only. Merge of `20261113_GALAXY_CAPABILITIES_LEVERAGE.md`, `20261113_GALAXY_WHAT_ELSE.md`, `20261113_FOLDER_AS_INPUT_GALAXY_LEVERAGE.md`, plus code verification. **No implementation; no sync.**

**Status legend**

| Status | Meaning |
|--------|---------|
| **Have** | Shipped in BioMate product UI/API and usable end-to-end |
| **Partial** | API/backend wired or half-UI; not end-to-end for users |
| **Missing** | Galaxy has it; BioMate does not expose it meaningfully |
| **Skip** | Intentionally not leveraging (one-word reason in note) |

Have / Partial rows cite at least one file path or route verified in-tree (not docs alone).

---

## Coverage table

| Capability | Status | Evidence/note |
|------------|--------|---------------|
| Nextflow / AWS Batch execute + SSE status | **Have** | `POST /api/workflows/execute` (`routes.ts`); panel SSE in `nextflow-workflow-viewer.tsx`; `nextflow_executor.py` |
| Pause / resume / rerun runs | **Have** | `POST /api/workflows/runs/:id/resume` (and related) used from `nextflow-workflow-viewer.tsx` |
| Autofix / deep diagnose | **Have** | `/api/galaxy/.../autofix3/*`, `POST /api/invocations/:id/ai/autofix`; panel autofix UI |
| Workflow chain (multi-workflow gates) | **Have** | `POST /api/workflows/chain`, `workflow_chain.py`; execute path in `routes.ts` |
| AI catalog search + workflow card / param strip | **Have** | `galaxy_ai_tools.db` + generate/search routes; `nextflow-workflow-viewer.tsx` |
| Findings + methods-report download | **Have** | Findings in panel / AfterRun; `GET /api/invocations/:id/methods-report`; `button-download-methods-report` |
| Software + citations endpoints | **Have** | `GET /api/invocations/:id/software`, `GET /api/workflows/:name/citations`; fetch hooks in `AfterRunReport.tsx` (unified Repro tab UI currently commented out) |
| Dataset lineage / versions / RO-Crate | **Have** | `/api/datasets/:ref/lineage\|consumers\|versions\|ro-crate` (`routes.ts`); Data Hub `datasets-api.ts` |
| Histories for staging + upload | **Have** | Session history + upload in `routes.ts` / `galaxy-api-proxy.ts`; chat attach path |
| Project files + S3 + Data Hub tree | **Have** | `project-routes.ts`, `project-file-tree.tsx`, `data-hub.tsx` |
| Folder profile + samplesheet **download** | **Have** | `GET …/folders/profile?download=samplesheet`; `folder_profile.py`; `folder-profile-view.tsx` |
| Folder → **all files** as Analysis attach | **Have** | `attachFolder` + `folder-as-input.ts`; Ask in chat on `folder-profile-view.tsx`; `chat-input.tsx` expands folder |
| Models / sandbox folder pick (expand to files) | **Have** | `dataset-selection.ts`, `training-launcher.tsx`, `code-sandbox-path.tsx` (`folderPath` / multi `fileIds`) |
| `run_code` sandbox (ad-hoc Python/R) | **Have** | `POST /api/code/run` (`routes.ts`); Models `code-sandbox-path.tsx`; assistant tool |
| Perception / datatype sniff | **Have** | `POST /api/perception/profile`; `perception.py`; Data Hub quality |
| Billing + internal quota (Stripe path) | **Have** | `/api/billing/*` proxy; `billing.tsx`; `quota_enforcer.py` (not Galaxy disk quotas) |
| Project members + share-link invite | **Have** | `/api/projects/:id/share-link`, members UI in `project-detail.tsx`; `join-project.tsx` |
| Per-user Galaxy API key provisioning | **Have** | `provisionGalaxyUser` in `galaxy-api-proxy.ts` |
| Connectors / credentials vault surface | **Have** | `connectors-dialog.tsx`; settings connections; vault-backed connector keys |
| Save run outputs to project | **Have** | save-to-project paths on execute / AfterRun (`routes.ts` + panel) |
| Step / file preview (tables, images, text, VCF table) | **Have** | `step-output-preview.tsx` — common formats; binary genomics still weak (see Display apps) |
| Deferred / large URL import | **Have** | Chat `UrlImportForm` + Data Hub defer/413→deferred; Confirm & Run / `POST /api/workflows/execute` materializes deferred HDAs via `deferred-materialize.ts` then stages for Batch (2026-11-13) |
| Remote public FTP/HTTP → project file | **Have** | Data Hub `RemoteSourcePicker` → sources/browse/fetch → `files/import-url` (2026-11-13). Agent/MCP unchanged |
| FASTQ folder → **samplesheet** as one Analysis input | **Have** | `POST …/folders/samplesheet` + folder **Use samplesheet** (complement **Attach all files**) — 2026-11-13 |
| Collections / HDCA create | **Partial** | `POST /api/collections*`; `createDatasetCollection` in proxy; **no** client UI; Nextflow rejects HDCA (`workflow-input-gate.ts`) |
| Pre-run cost estimate badge | **Partial** | `GET\|POST /api/workflows/estimate_cost` wired; `CostEstimateBadge` removed from panel (`wiring-contracts.test.ts` asserts absent); billing page shows usage after the fact |
| Post-run cost on Runs / panel strip | **Partial** | Billing ledger + panel vCPU meter (`nextflow-workflow-viewer.tsx`); no estimate-vs-actual Runs-row strip |
| Reproducibility pack (one zip) | **Have** | `GET /api/runs/:id/reproducibility-pack` (`reproducibility-pack.ts` + `routes.ts`); AfterRun + panel `button-download-repro-pack` — methods snapshot + software + citations + run-record + run RO-Crate (2026-11-13). Not Galaxy `/tmp` bundle; not download-all |
| Perception → Confirm & Run datatype gate | **Have** | `perceptionMismatch` in `input-mapping-status.ts` → `isPrereqBlocked` (2026-11-13); strong kinds only |
| Native Galaxy `.ga` invoke | **Partial** | Upload accepts `.ga` into `personal_workflows` (`POST /api/workflows/upload-file`); execute path is Nextflow/`file_content`-oriented — not honest Galaxy-engine invoke UX |
| Galaxy invoke API (proxy) | **Partial** | `invokeWorkflow` + `/api/galaxy/workflows/...` exist; product default engine is Nextflow |
| Subworkflow extract | **Partial** | `POST /api/workflows/:id/extract-subworkflow`; `extractSubworkflow` in proxy; no product UI |
| Interactive Tools (Jupyter/RStudio/cellxgene) | **Partial** | Routes `/api/interactive/*`, open-in handlers exist; `OPEN_IN_AVAILABLE = false` (`dataset-view-model.ts`); `INTERACTIVE_TOOLS_ENABLED` gate in `routes.ts` — buttons hidden |
| Genome builds (igenomes) | **Partial** | Silent resolve on execute (`nextflow_executor.py`); no user-facing `GET /api/genomes` browser / build picker |
| Extra remote file-source plugins (Drive/WebDAV/…) | **Partial** | Galaxy supports many plugins; BioMate `file_sources_conf.yml` only public FTP/HTTP set |
| Workflow landings (shareable pre-filled invoke UUID) | **Missing** | Galaxy `workflow_landings` API in-tree; BioMate has library/deep links only |
| Extract workflow from history | **Missing** | Galaxy `from_history_id` / `workflow/extract.py`; no BioMate “save completed run as reusable workflow” |
| Built-in datatype converters (~98) | **Missing** | Galaxy converters registry; BioMate does not auto-convert (e.g. BAM→BAI) before Batch |
| Collection operation tools (zip/filter/relabel/rules) | **Missing** | Semantics useful for samplesheets; not productized on project_files |
| Rule-based uploader / Apply Rules | **Missing** | Stronger than folder expand for multi-lane clinical FASTQ |
| Display applications (IGV, UCSC, Ensembl, …) | **Missing** | Configs in Galaxy; BioMate BAM/VCF/h5ad still download / IT-gated — no IGV.js product viewer |
| Visualizations registry / viz plugins | **Missing** | `visualizations.py` unused by product UI |
| Published histories / anonymous history share URLs | **Missing** | Galaxy `enable_link_access` / published histories; BioMate sharing is project membership + share-link (different model — Have above) |
| Storage cleaner / archive / purge UX | **Missing** | Galaxy `/api/storage/*`; no S3 abandoned-run cleanup product UX |
| In-app notifications (run-complete / QC) | **Missing** | Galaxy `/api/notifications/*`; BioMate uses chat/SSE only |
| GA4GH DRS | **Missing** | `/ga4gh/drs/v1/...` present in Galaxy; not a BioMate partner ingest path |
| Tags + annotations (searchable) | **Missing** | Galaxy item_tags/annotations; BioMate project notes ≠ faceted dataset tags |
| Pages + Galaxy Markdown PDF | **Missing** | `/api/pages`; adjacent to CRO packages but unused |
| Job `build_for_rerun` / destination_params | **Missing** | Useful for Galaxy-job honesty; Nextflow rerun already Have via BioMate |
| Tool-sequence recommendations model | **Missing** | Galaxy `tools/recommendations.py`; low value while catalog is LLM-ranked Nextflow |
| History/invocation model-store export | **Missing** | Broader than methods-report; complements planned repro zip |
| Workflow export / publish / share GA URLs | **Missing** | Galaxy share/publish APIs; BioMate library is Postgres-centric |
| Galaxy job metrics API | **Missing** | Prefer BioMate billing Redis / estimate_cost (see Partial cost rows) |
| Data Libraries (LDDA trees) | **Skip** | ACL-dupe — use projects/S3 |
| Galaxy disk quotas | **Skip** | Stripe — internal quota |
| Galaxy roles / groups | **Skip** | RBAC — project members / Team plan |
| Tool Shed live install / dynamic tools | **Skip** | Containers — curated DB + pinned images |
| TRS / Dockstore as primary catalog | **Skip** | Catalog — indexed Nextflow first |
| Pulsar | **Skip** | Batch — already remote runner |
| CVMFS | **Skip** | S3 — igenomes resolution |
| TPV | **Skip** | Queues — Batch cost model |
| OIDC (Galaxy IdP) | **Skip** | Auth — BioMate JWT/MFA |
| Galaxy viz iframes / classic tool-form UX | **Skip** | Product — workflow panel + Batch |
| HDCA → Nextflow param binding | **Skip** | Engine — use samplesheet/S3 lists |
| Forms (admin) / Tours | **Skip** | Onboarding — not BioMate UX |
| Interactive Tools as default ad-hoc compute | **Skip** | Sandbox — `run_code` is supported path (wiring kept Partial above) |

---

## High-value Missing (users would care)

Cap for chat summary; full Missing rows remain in the table.

1. ~~Deferred materialize on Confirm & Run~~ → **Have** (2026-11-13)  
2. ~~Reproducibility pack zip~~ → **Have** (2026-11-13)  
3. Inline estimate vs actual run cost  
4. BAM/VCF/(h5ad) viewers without IT (IGV.js-class)  
5. Datatype auto-converters before Batch  
6. Workflow landing / shareable pre-filled run links  
7. Storage archive/purge for abandoned S3 data  
8. In-app run-complete / QC notifications  
9. Honest `.ga` → Galaxy-engine (or clear “Nextflow only”) labeling  

Shipped from this list on 2026-11-13 (deep session): remote browse → project_files; FASTQ samplesheet-as-one Analysis input; perception Confirm & Run datatype gate; deferred import in primary chat/Data Hub UX; materialize-on-Confirm&Run; reproducibility pack zip.

---

## Related docs

- `docs/20261113_GALAXY_CAPABILITIES_LEVERAGE.md` — top leverage + conflicts  
- `docs/20261113_GALAXY_WHAT_ELSE.md` — residual Galaxy surface + skip list  
- `docs/20261113_FOLDER_AS_INPUT_GALAXY_LEVERAGE.md` — folder/HDCA/samplesheet detail (note: folder→all-files and Models folder pick have since shipped; samplesheet-as-input still open)

---

**Document only.** Commit this file; no sync; no feature code.
