# Galaxy “what else” — beyond the top-5 leverage list

**Date:** 2026-11-13  
**Trigger:** User follow-up — “We have most of the abilities. What else does it have?”  
**Prerequisite:** `docs/20261113_GALAXY_CAPABILITIES_LEVERAGE.md` (do not re-plan the top 5).  
**Scope:** Document only. No implementation, no sync.

---

## Already have (brief)

BioMate already productizes Galaxy as the execution + AI substrate:

- Nextflow/Batch runs, SSE status, pause/resume/rerun, autofix, workflow chain  
- AI catalog search / param extraction / findings / methods-report / software / citations / RO-Crate endpoints  
- Histories for staging, project_files + S3, upload / import-url, perception sniffing  
- Collections + deferred-dataset **APIs** (UI/engine incomplete — see top 5)  
- Remote FTP/HTTP file sources config (`file_sources_conf.yml`) + `/api/data/*`  
- Vault-backed credentials (connectors, private DB, external MCP)  
- `run_code` sandbox (deliberate substitute for Interactive Tools)  
- Billing / internal quota (not Galaxy disk quotas)

**Near-term leverage already listed (do not re-rank here):** remote public fetch → project_files; deferred URL materialize; FASTQ samplesheet attach; reproducibility pack zip; perception Confirm&Run datatype gate.

---

## Galaxy still has that we don’t use

Concrete Galaxy features present in-tree (`backend/lib/galaxy/...`) that are **not** fully productized in BioMate UI and **not** in the top-5 list. One line each: what it is + why it might matter.

1. **Extract workflow from history** (`workflow/extract.py`, `POST /api/workflows` `from_history_id`) — turn a successful tool/job chain into a reusable `.ga`; BioMate could offer “Save this completed run as a reusable workflow” for Galaxy-engine or audit trails.  
2. **Workflow landings** (`POST /api/workflow_landings`, claim/get) — shareable UUID that opens a pre-filled invoke; useful for CRO handoff / “run this exact ADMET card” deep links beyond today’s library links.  
3. **Workflow export styles + share/publish API** (export / editor / format variants; enable_link_access / publish on workflows) — portable GA export and public workflow URLs; BioMate library is Postgres-centric and does not expose Galaxy’s shareable GA surface.  
4. **Job `build_for_rerun` + `destination_params`** (`GET /api/jobs/{id}/build_for_rerun`, `/destination_params`) — rebuild tool form state and show which runner/resources ran; could power honest “rerun with same params” for Galaxy jobs and admin debugging of Batch vs local destinations.  
5. **Built-in datatype converters (~98)** (`datatypes/converters/*`, `GET /api/datatypes/converters`) — BAM→BAI/bigWig, FASTA→FAI/len, CRAM→BAM, CSV→tabular, decompressors, etc.; auto-convert before a tool/Batch step instead of failing on missing indexes.  
6. **Collection operation tools** (`__ZIP__` / `__UNZIP__` / `__FILTER_FAILED__` / `__SORT__` / `__RELABEL__` / `__APPLY_RULES__` / merge / flatten / extract) — first-class list surgery; for BioMate the value is the **semantics** (filter failed samples, relabel, sort) mapped to project_files/samplesheets — not binding HDCAs into Nextflow.  
7. **Rule-based uploader / Apply Rules** (`__APPLY_RULES__`, upload rule builder) — map messy multi-file drops into paired/list collections via column rules; stronger than “expand folder” for clinical multi-lane FASTQ layouts.  
8. **Genome builds API** (`GET /api/genomes`, indexes, sequence slices) — installed dbkeys, chrom lengths, raw sequence windows; BioMate silently resolves igenomes on execute but has no user-facing genome browser / build picker backed by this API.  
9. **Display applications** (`datatypes/display_applications/configs`: IGV, UCSC, Ensembl, iobio, …) — open BAM/VCF/genome tracks in external or embedded viewers; BioMate step preview is tables/images/text-heavy — binary genomics still “download-ish.”  
10. **Visualizations registry** (`/api/visualizations`, datatype→viz mappings) — charts/plugins attached to history datasets; unused; could inspire AfterRun plot cards without embedding Galaxy iframes.  
11. **Pages + Galaxy Markdown** (`/api/pages`, PDF export of Markdown with embedded datasets) — shareable lab-notebook / methods page with live dataset refs; adjacent to CRO/IND packages but not the same as BioMate findings HTML.  
12. **Published histories + history/dataset share links** (`/api/histories/published`, `enable_link_access`) — one-click share of an entire analysis history; BioMate project sharing is membership-scoped, not anonymous history URLs.  
13. **Storage cleaner / archive / purge** (`/api/storage/*`, history archive) — discarded/archived size summaries + permanent purge; maps to S3 cost control for abandoned runs/datasets (product UX missing).  
14. **Galaxy tool-sequence recommendations** (`tools/recommendations.py` transformer model on prior tool IDs) — “users who ran A→B next used C”; orthogonal to BioMate’s LLM workflow ranking; only useful if Galaxy-tool invoke volume grows.  
15. **In-app notifications** (`/api/notifications/*`) — user + broadcast channels with preferences; BioMate relies on chat/SSE; could cover run-complete / QC-fail / share-claim without polling.  
16. **GA4GH DRS** (`/ga4gh/drs/v1/...`) — stable object IDs + access URLs for federated data exchange; relevant if partners hand BioMate DRS URIs instead of S3/HTTP.  
17. **History / invocation model-store export** (short-term storage + export-store APIs) — portable archive of an invocation’s inputs/outputs/metadata; complements (but is broader than) the planned reproducibility zip.  
18. **Tags + annotations** (`item_tags`, `annotations` APIs) — free-text notes and faceted tags on histories/datasets/workflows with Galaxy search operators; BioMate project notes ≠ searchable dataset tags.  
19. **Extra remote file-source plugins** (Galaxy supports WebDAV, Dropbox, Google Drive, GCS, Azure, OneData, BaseSpace, remotezip — tests exist; BioMate `file_sources_conf.yml` only enables EBI/NCBI/Ensembl/UCSC FTP + HTTP) — institutional / cloud-drive browse beyond public FTP (top-5 covers *using* the FTP path, not enabling these plugins).

---

## Exists but we should skip

(Unless a customer explicitly pulls them onto the critical path.)

| Feature | Why skip for BioMate |
|---------|----------------------|
| **Pulsar** | Remote job proxy; BioMate already routes heavy work via AWS Batch / Nextflow runners. |
| **CVMFS** | Reference-data mount fabric for classic Galaxy nodes; BioMate uses S3 + igenomes resolution. |
| **TPV (Total Perspective Vortex)** | Dynamic job destination mapping; conflicts with Batch queue / cost model. |
| **OIDC login** | Galaxy IdP wiring; BioMate owns auth (JWT, MFA, Stripe tiers). |
| **Galaxy disk quotas / roles / groups** | Duplicates Stripe + project membership RBAC. |
| **Data Libraries (LDDA)** | Institutional share trees; map to shared projects/S3 prefixes instead. |
| **Interactive Tools (Jupyter/RStudio)** | Wired but gated off; `run_code` is the supported ad-hoc path. |
| **Tool Shed live install / dynamic tools** | Ops-heavy; conflicts with pinned Batch containers + curated `galaxy_ai_tools.db`. |
| **TRS / Dockstore consumer as primary catalog** | Nice import edge; catalog strength is indexed Nextflow, not live TRS browse. |
| **Galaxy viz iframes / classic tool-form UX** | Forks the product away from workflow panel + Batch. |
| **HDCA → Nextflow param binding** | Engine rejects; use samplesheet/S3 lists. |
| **Forms (admin)** | Galaxy signup/admin forms; not BioMate product UX. |
| **Tours / GUIDES** | Galaxy onboarding walkthroughs; BioMate needs its own product tours if any. |
| **API allowlists / sanitize allow** | Admin hardening knobs, not user features. |

---

## How this relates to the leverage doc

- Keep implementing **top 5** from `20261113_GALAXY_CAPABILITIES_LEVERAGE.md` first.  
- Treat items **1–3, 5, 8–9, 12–13, 15, 19** above as the next discovery tier if the user still wants more Galaxy leverage after the top 5.  
- Prefer **porting semantics** (converters, share links, archive/purge, notifications, rule upload) into BioMate’s project_files / Runs / Data Hub plane over re-exposing classic Galaxy UI.

---

**Document only.** Commit this file; no sync; no feature code.
