# BioMate Data Connector Landscape — Planning Document

**Date:** 2026-06-18  
**Scope:** Connector architecture concerns, Galaxy file source inventory, Galaxy object store inventory, AI tools DB data source findings, gap analysis, and prioritized recommendations.

---

## 1. Connector Architecture Concern: Interface-Coupled vs Pure API

### The Problem

The current BioMate MCP connector has two layers that are conflated:

**Layer 1 — Pure code (works headlessly):**
```
User prompt → Claude → tools/call → MCP server → BioMate API → result JSON
```

**Layer 2 — Interface-dependent (the gap):**
- OAuth PKCE browser pop-up: `npx @biomate/connect` opens a browser for auth
- `view_url` as the primary result: responses return a link to the BioMate web dashboard instead of inline structured data
- Parameter disambiguation: when multiple workflows match, currently implies "go look at the UI"
- File upload: assumes the BioMate web interface for non-S3 inputs

Users in Claude Code, Cursor, CI pipelines, or lab automation scripts cannot click links or open a browser mid-run.

### Two Connector Modes Required

| Mode | Auth | Interaction | Results | Use case |
|------|------|-------------|---------|----------|
| **Headless / API key** | `BIOMATE_API_KEY` env var | MCP `sampling/createMessage` for inline choices | Full JSON + optional `view_url` | Claude Code, Cursor, Codex CLI, CI, lab instruments |
| **OAuth / browser** | OAuth 2.1 PKCE browser flow | BioMate UI for complex forms | JSON + `view_url` | Claude Desktop, Slack, ChatGPT, WeChat |

The MCP server detects mode from the env and adjusts. Lab instrument connectors always use API key mode (zero human in loop).

### MCP Protocol Capabilities Not Yet Used

- **`sampling/createMessage`** — server asks Claude to collect user input inline; surfaces as a native Claude Code popup/prompt. Should replace any flow that currently redirects to the BioMate UI.
- **Tool `annotations`** with `x-interactive: true` — signals the host that a tool call may need user input before executing.
- **`roots`** capability — tells the host which file system scopes the server cares about.

### Decision: It's the User's Choice

Whether to use the inline (headless) or interface mode should be user-configurable. Both modes must work correctly. The connector release should ship with API key mode fully functional; OAuth mode is the secondary path.

---

## 2. Galaxy File Source Plugins — Full Inventory

**Location:** `backend/lib/galaxy/files/sources/`  
**Total:** 25 plugins

### Cloud Storage (browsable, per-user credentials)

| Plugin | File | Protocol | Credentials |
|--------|------|----------|-------------|
| S3 / S3-compatible | `s3fs.py` → `S3FsFilesSource` | AWS S3, MinIO, Ceph | access key + secret |
| Azure Blob Storage | `azure.py` → `AzureFileSource` | Azure Blob | account name + key |
| Google Drive | `googledrive.py` → `GoogleDriveFilesSource` | GDrive | OAuth2 access token |
| Google Cloud Storage | `googlecloudstorage.py` → `GoogleCloudStorageFilesSource` | GCS | project + credentials |
| Dropbox | `dropbox.py` → `DropboxFilesSource` | Dropbox | OAuth2 access token |

### Standard Protocols (browsable, per-user config)

| Plugin | File | Protocol | Credentials |
|--------|------|----------|-------------|
| FTP | `ftp.py` → `FtpFilesSource` | FTP | host/user/pass (or anonymous) |
| SSH / SFTP | `ssh.py` → `SshFilesSource` | SFTP | host/user/key or pass |
| WebDAV | `webdav.py` → `WebDavFilesSource` | WebDAV / OwnCloud / NextCloud | URL + user/pass |
| POSIX / Local | `posix.py` → `PosixFilesSource` | Local filesystem | root path |
| Onedata | `onedata.py` → `OnedataFilesSource` | Onedata distributed | host + token |

### Research Data Repositories (browsable, API token)

| Plugin | File | Handles | Notes |
|--------|------|---------|-------|
| Zenodo | `zenodo.py` → `ZenodoFilesSource` | Zenodo open-access repository | Read + write; `writable: true` |
| InvenioRDM | `invenio.py` → `InvenioRDMFilesSource` | InvenioRDM instances | Read + write |
| Dataverse | `dataverse.py` → `DataverseFilesSource` | Harvard Dataverse network | Read + write |
| Anvil | `anvil.py` → `AnvilFilesSource` | Anvil genomics cloud (NIH) | workspace + billing_project |

### Scientific / Domain-Specific (browsable)

| Plugin | File | Handles |
|--------|------|---------|
| Illumina BaseSpace | `basespace.py` → `BasespaceFilesSource` | BaseSpace sequencing runs (OAuth2) |
| RSpace ELN | `rspace.py` → `RSpaceFilesSource` | RSpace electronic lab notebook |
| eLab FTW | `elabftw.py` → `ElabFTWFilesSource` | eLab FTW lab notebook |

### Single-File / Non-browsable Sources

| Plugin | File | Handles |
|--------|------|---------|
| HTTP / HTTPS | `http.py` → `HTTPFilesSource` | Any public URL |
| DRS | `drs.py` → `DRSFilesSource` | GA4GH Data Repository Service URIs |
| RemoteZip | `remotezip.py` → `RemoteZipFilesSource` | ZIP files from remote URLs |
| Galaxy | `galaxy.py` → `GalaxyFilesSource` | Other Galaxy instances |
| Base64 | `base64.py` → `Base64FilesSource` | Inline base64-encoded data |
| Temp | `temp.py` → `TemporaryFilesSource` | Temporary workflow files |

### Current BioMate Status

`backend/config/galaxy.yml` has **no `file_sources_conf` entry**. All 25 plugins are present in the codebase but **none are enabled** in BioMate's production config. The API routes exist (`/api/file_source_instances`, `/api/remote_files`, `/api/file_source_templates`) but there is no frontend UI for any of them.

---

## 3. Galaxy Object Store Plugins — Full Inventory

**Location:** `backend/lib/galaxy/objectstore/`  
These are storage backends for Galaxy's internal dataset storage (different from file sources — these store BioMate's own output files).

### Cloud Object Stores

| Plugin | File | Handles | Features |
|--------|------|---------|---------|
| AWS S3 (boto3) | `s3_boto3.py` → `S3ObjectStore` | AWS S3 | Caching, multipart, CloudFront CDN |
| AWS S3 (legacy) | `s3.py` → `GenericS3ObjectStore` | S3-compatible (MinIO, etc.) | Legacy boto |
| Azure Blob | `azure_blob.py` → `AzureBlobObjectStore` | Azure Block Blob | Caching, concurrent transfers |
| Google Cloud | `cloud.py` → `Cloud` | GCP Cloud Storage | Caching, parallel uploads |

### HPC / Enterprise Storage

| Plugin | File | Handles | Features |
|--------|------|---------|---------|
| iRODS | `irods.py` → `IRODSObjectStore` | iRODS (EMBL, Sanger, DKFZ, etc.) | Caching, federation |
| Onedata | `onedata.py` → `OnedataObjectStore` | Onedata distributed | Geo-redundancy |
| Pithos | `pithos.py` → `PithosObjectStore` | Synnefo / GRNET | Caching |
| Rucio | `rucio.py` → `RucioObjectStore` | CERN / HEP data management | Distributed, federation |
| Pulsar | `pulsar.py` → `PulsarObjectStore` | Remote Pulsar compute nodes | Transfer protocol |

**Sample configs** available at `backend/lib/galaxy/config/sample/object_store_conf.sample.yml` for all backends.  
**Current BioMate status:** Uses default disk storage. No `object_store_config` in `galaxy.yml`.

---

## 4. S3 Status — Already Fully Enabled at Execution Layer

**Conclusion: S3 is deeply integrated in BioMate. This was already done.**

Evidence in `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`:
- Env vars: `NEXTFLOW_USE_AWS`, `NEXTFLOW_S3_BUCKET` (default: `biomate-nextflow-work`)
- `_S3_OUTPUT_REQUIRED_DOMAINS` frozenset — certain workflow domains force S3 output
- Pre-flight boto3 validation of `s3://` input URIs before job launch
- Full `s3://` URI handling in parameter normalization

Evidence in `frontend/server/routes.ts`:
- File upload → S3 staging (`s3://biomate-nextflow-work/inputs/<userId>/...`)
- Output retrieval from S3
- S3 credential test endpoint (line ~6144)

**What S3 does NOT have:** a Galaxy file source browser for users to browse their own S3 buckets and pick input files. They must type `s3://` paths manually. Enabling `S3FsFilesSource` in `file_sources_conf.yml` would add this UI.

---

## 5. AI Tools DB — Data Source & Database Connector Findings

**Database:** `backend/database/galaxy_ai_tools.db`  
**Total tools in "Data Source" category:** 138

### SQL and Database Tools

| Tool | Category | What it does |
|------|----------|--------------|
| `Postgresql` | Data Export | PostgreSQL running containerized in user-space; DB packed as tarball in Galaxy history |
| `Query` | Data Export | Query the containerized PostgreSQL instance above |
| `SQL` | Convert Formats | Generic SQL query tool |
| `SQLite to tabular` | Text Manipulation | Run SQL queries against SQLite files |
| `mz to sqlite` | Convert Formats | Mass spec data → SQLite |
| `BAM to Sqlite` | Transcriptomics | BAM alignments → SQLite for TRIPS-Viz |
| `SQLDataFrame` | DataRepresentation | Bioconductor: SQL-backed DataFrame/DelayedArray for SummarizedExperiments |
| `MsBackendSql` | DataImport | SQL backend for mass spec Spectra objects (very large datasets) |
| `NCBI Taxonomy SQLite builder` | Data Managers | Builds SQLite version of NCBI Taxonomy |
| `Save Sequence Data In DB` | Synthetic Biology | Writes to external `postgresql://` URI (actual external DB connector) |

**Important distinction:** The `Postgresql`/`Query` tools run a local containerized PostgreSQL — they are not connectors to external DB servers. `Save Sequence Data In DB` IS a real external connector (takes a `postgresql://` connection string).

### iRODS — Well Covered (5 tools)

iRODS is the standard institutional storage system at EMBL, Wellcome Sanger, DKFZ, and most major genomics centers.

| Tool | What it does |
|------|--------------|
| `iBridges browser for iRODS` | Interactive browser (runs as a Galaxy interactive tool) |
| `iBridges download from iRODS` | Download files/collections by iRODS path |
| `iBridges upload to iRODS` | Upload to iRODS by path |
| `iRODS Download` | Direct download |
| `iRODS Upload` | Direct upload |

### FHIR / Clinical Data

| Tool | Category | What it does |
|------|----------|--------------|
| `BiocFHIR` | DataImport | Parses FHIR R4 JSON bundles (Synthea format); transforms to R tables |
| `CLINICALTRIALS` | Data Source | ClinicalTrials.gov data source (trial search, recruitment status, results) |
| `CLINVAR` | Data Source | ClinVar variant pathogenicity data source |

### Public Genomics Archives (138 Data Source tools, key ones)

| Tool / Workflow | What it fetches |
|-----------------|----------------|
| `nf-core/fetchngs` (workflow) | SRA / ENA / DDBJ / GEO accessions → FASTQ |
| `Fastq Download Prefetch Fasterqdump Sratools` | NCBI SRA → FASTQ |
| `Geo Data Connector` (workflow) | GEO accession → count matrix + clinical metadata, ready for RNA-seq |
| `GEOfastq`, `GEOquery`, `GEOexplorer` | GEO microarray and RNA-seq data |
| `SRAdb` | SRA metadata queries from R |
| `EBI Search`, `Retrieve ENA data` | ENA search and download |
| `NCBI EFetch`, `NCBI ESearch`, etc. | Full NCBI E-utilities suite |
| `NCBI Datasets Gene`, `NCBI Datasets Genomes` | Bulk genome/gene downloads |
| `Atlas FASTQ provider` | Human Cell Atlas (HCA Azul) |
| `EGA Download Client / streamer` | European Genome-phenome Archive (controlled access) |
| `SYNAPSE` | Sage Bionetworks Synapse platform |
| `HuBMAPR` | HuBMAP human body atlas |
| `CBIOPORTAL` | Memorial Sloan Kettering cancer genomics portal |
| `PDB`, `UNIPROT`, `INTERPRO`, `STRINGDB` | Structure/protein databases |
| `GNOMAD`, `DBSNP`, `GWAS_CATALOG`, `REGULOMEDB` | Variant databases |
| `REACTOME`, `KEGG`, `JASPAR` | Pathway and regulatory databases |
| `Mongo Client` | MongoDB connector |
| `CouchDB Client` | CouchDB connector |
| `SPARQL Query Tool` | SPARQL endpoint queries (Uniprot, Wikidata, etc.) |
| `Uniprot Sparql` | UniProt SPARQL endpoint |

### Workflows That Pull Public Data

| Workflow | Domain | Data it fetches |
|----------|--------|-----------------|
| `Geo Data Connector` | genomics | GEO accession → RNA-seq-ready inputs |
| `Wgs Germline Gatk` | genomics | Accepts SRA accession as input |
| `nf-core/fetchngs` | general | SRA/ENA/DDBJ/GEO → FASTQ |
| `GEOfastq`, `GEOquery` | transcriptomics | GEO data retrieval |
| `SRAdb` | genomics | SRA metadata |

---

## 6. Gap Analysis

### What Exists but BioMate Doesn't Expose

| Capability | Status | Effort to Enable |
|-----------|--------|-----------------|
| S3 file browser (user's own buckets) | Plugin exists, no config | Low — add `file_sources_conf.yml` entry |
| Anonymous FTP (EBI, NCBI, Ensembl) | Plugin exists, no config | Very low — no credentials needed |
| WebDAV / OwnCloud / NextCloud | Plugin exists, no config | Low — user provides URL/credentials |
| SFTP / SSH | Plugin exists, no config | Low — user provides host/key |
| Zenodo / Dataverse / InvenioRDM | Plugin exists, no config | Low — user provides API token |
| BaseSpace file browser | Plugin exists, no config | Medium — OAuth2 flow |
| RSpace / eLab FTW | Plugin exists, no config | Low — user provides API token |
| iRODS | Plugin + 5 tools exist, not prominent | Low — config + surface in UI |
| GEO / SRA accession input | Workflow exists, not exposed in MCP | Low — expose via MCP tool |
| SPARQL queries | Tool exists | Medium — surface in `query_database` |

### True Gaps (Doesn't Exist Anywhere)

| Capability | Notes |
|-----------|-------|
| External PostgreSQL/MySQL connector | `Save Sequence Data In DB` writes to Postgres, no read connector |
| Snowflake / BigQuery / Redshift | Not present |
| REDCap API | Not present; critical for clinical genomics |
| OMOP CDM / i2b2 | Not present; standard clinical data models |
| FHIR read/write (beyond bundle parsing) | `BiocFHIR` only parses static bundles; no live FHIR server connector |

---

## 7. Recommendations and Priorities

### Tier 1 — Low effort, high value (enable existing Galaxy capabilities)

1. **Enable anonymous public FTP sources in `file_sources_conf.yml`**  
   EBI FTP, NCBI FTP, Ensembl FTP — zero credentials, massive reference data access.  
   File: `backend/config/file_sources_conf.yml` (create this file).

2. **Enable S3 file source browser**  
   Add `S3FsFilesSource` to `file_sources_conf.yml` with user-preference template (credentials per user, not system-wide). This gives the UI to browse `s3://` paths rather than typing them.

3. **Add `fetch_public_data` MCP tool**  
   Wrap the `fetchngs` / `Geo Data Connector` / SRA workflows. A user should be able to say "run RNA-seq on GSE183947" and have the connector resolve the GEO accession → FASTQ fetch → pipeline automatically.

4. **Surface iRODS in the connector**  
   iRODS tools are in the DB. Add `irods://` URI support alongside `s3://` in the MCP server. High value for institutional users at EMBL, Sanger, DKFZ.

5. **Expose Zenodo / Dataverse in `query_database` or new `browse_data` tool**  
   Published research datasets in these repositories are a natural input for BioMate workflows. A `browse_data` MCP tool wrapping `/api/remote_files` would let Claude browse these inline.

### Tier 2 — Medium effort, high strategic value

6. **API key auth mode for MCP connector**  
   Replace browser OAuth requirement for code-surface users. Single env var `BIOMATE_API_KEY`. Removes the last "interface-dependent" blocker for headless use.

7. **MCP `sampling/createMessage` for disambiguation**  
   Replace any flow that redirects to BioMate UI for parameter collection with inline MCP sampling. Claude Code surfaces this as a native popup.

8. **Inline structured results**  
   Every tool response should return full structured data (findings JSON, output file previews) as the primary result. `view_url` becomes supplementary.

9. **Enable WebDAV, SFTP, Zenodo per-user file sources**  
   Frontend UI for users to register their own cloud/storage connections. Galaxy's `/api/file_source_instances` API already supports this.

### Tier 3 — Requires new development (genuine gaps)

10. **REDCap API connector**  
    Critical for clinical genomics. REDCap is the dominant clinical data capture system. Needs a new Galaxy tool or BioMate-level connector.

11. **OMOP CDM / i2b2 connector**  
    Standard clinical data models used at most academic medical centers. Enables real EHR-linked genomics workflows.

12. **Live FHIR server connector**  
    Beyond `BiocFHIR`'s static bundle parsing — a connector to live FHIR R4 endpoints (Epic, Cerner, Azure Health APIs). Enables precision medicine workflows.

13. **External SQL read connector**  
    A Galaxy tool (or BioMate connector) that queries an external PostgreSQL/MySQL by connection string and returns results as a dataset. `Save Sequence Data In DB` does the write side; the read side is missing.

---

## 8. Connector Release Checklist (Data Layer)

For the public connector release (`bioMate-AI/biomate-connector`), the data connection story should cover:

- [ ] `run_workflow` accepts `s3://`, `irods://`, `drs://`, `https://` URIs natively
- [ ] `fetch_public_data` tool: GEO/SRA/ENA accession → auto-fetches and submits
- [ ] `browse_data` tool: wraps `/api/remote_files` for inline file browsing from Claude
- [ ] API key auth: `BIOMATE_API_KEY` env var, no browser required
- [ ] Docs: which file source types are supported, how to configure per-user cloud storage

---

*Generated from conversation 2026-06-18. Sources: Galaxy codebase at `/Users/kky/biomate/backend/lib/galaxy/`, AI tools DB at `backend/database/galaxy_ai_tools.db`, `nextflow_executor.py`, `routes.ts`.*
