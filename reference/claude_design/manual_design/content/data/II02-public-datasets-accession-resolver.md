# Public datasets & the accession resolver

> One-line promise: after this page you can point BioMate at data that already lives in a public archive
> — by accession or by URL — and get it into a run, and you'll know exactly which archives are really
> supported. For everyone who starts from published data rather than their own files.

<!--
Reference chapter (Part II). Template-adapted for a data/retrieval reference.
Every "supported" claim is code-verified (tier C). Repositories are verified one-by-one against the
resolver code; anything listed-but-unsupported is called out and pushed to Appendix E.
See the ledger rows at the foot of this page.
-->

## What this is for

A lot of analysis starts from data someone already deposited — a GEO series, an SRA run, a file on an
EBI/NCBI FTP server. BioMate has two front doors for that:

1. **The accession resolver** — you give it a public **accession** (e.g. `GSE183947`, `SRR12345`) and it
   tells you which fetch workflow will pull that data and pre-fills the parameter, ready to run.
2. **Fetch / import by URL** — for a file you can already point at (FTP path or HTTPS/S3 URL), BioMate
   stages it into your workspace as a dataset with no manual download.

This page is honest about scope: it documents only the archives the code actually resolves, and flags
the ones that *look* supported (they appear in a tool description or a detector) but do **not** have a
working resolver.

## Use cases

| Goal (researcher's words) | Path | Input | Result (artifact) | Lane |
|---|---|---|---|---|
| "Analyse GEO series GSE183947" | `resolve_accession` → run the resolved fetch workflow | GEO accession | Count matrix + clinical metadata (Geo Data Connector), ready for DE | Cloud |
| "Get the FASTQs for SRR/ERR/DRR run(s) or a BioProject" | `resolve_accession` → `nf-core/fetchngs` | SRA/ENA/DDBJ run / project accession | Raw FASTQ + metadata in S3, feedable into rnaseq/sarek | Cloud |
| "Pull a reference file from the EBI/NCBI/Ensembl/UCSC FTP" | `browse_data` → `fetch_public_data` | source + remote path | File staged to S3 (`s3://…`) + presigned URL | Instant→Cloud |
| "Import this file I already have a URL/S3 path for" | Composer → data browser → **From URL** | HTTPS/FTP/S3 URL | A dataset object you can select as a workflow input | Instant |

## How to ask

> "Fetch and analyse GSE183947." — resolver classifies GEO → Geo Data Connector; runs when you confirm.

> "Download the FASTQ files for PRJNA575612." — resolver classifies a BioProject → nf-core/fetchngs.

> "Import this file: `https://ftp.ensembl.org/…/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz`." —
> use the composer's **From URL** tab; no accession lookup needed.

**The disambiguation to avoid:** an accession chooses the *fetcher*, not the *analysis*. Resolving
`GSE…` gets you a count matrix; you still route the downstream DE/enrichment separately (see II.1 and the
Transcriptomics chapter). And a **URL import** is not accession resolution — it stages a file as-is with
no workflow recommendation.

## Which repositories are really supported

The active resolver is `POST /api/accession/resolve` in `frontend/server/routes.ts:8532-8622`. It
pattern-matches the accession and returns the fetch workflow + a pre-filled param. Verified against the
code, the **really supported** set is:

| Archive | Accession patterns | Resolves to | Evidence |
|---|---|---|---|
| **GEO** (series / dataset / sample) | `GSE…`, `GDS…`, `GSM…` | **Geo Data Connector** (id 10672) — GEOquery series matrix + metadata | `routes.ts:8552-8571` |
| **SRA / ENA / DDBJ** (runs, experiments, samples, studies) | `SRR/SRX/SRS/SRP`, `ERR/ERX/ERP`, `DRR/DRP` | **nf-core/fetchngs** (id 12704) — raw FASTQ + metadata to S3 | `routes.ts:8574-8582` |
| **BioProject** | `PRJNA…`, `PRJEB…`, `PRJDB…` | nf-core/fetchngs | `routes.ts:8574` |
| **ArrayExpress / BioStudies** | `E-MTAB-…`, `E-GEOD-…` (any `E-<letters>-<digits>`) | nf-core/fetchngs (via its EBI path) | `routes.ts:8574` (catch-all `E-[A-Z]+-\d+`) |

Everything else returns a `422 Unrecognised accession format` with a hint listing the supported prefixes
(`routes.ts:8590-8595`).

> **Pitfall — PDB, EMDB, PRIDE, MassIVE are NOT resolvable.** BioMate's backend has *detectors* for
> `PDB`, `EMD-…`, `PXD…` (PRIDE), `MSV…` (MassIVE), UniProt/RefSeq/Ensembl/ChEMBL/PubChem/dbSNP/ClinVar
> — but those live in the run-input **validation** registry
> (`backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:576-709`), where they only tell the
> executor "this looks like an accession, don't fail as a missing file." They are **not** wired to
> `resolve_accession`, so pasting a PDB ID or a PRIDE accession to the resolver returns 422. Fetch a
> structure or a proteomics deposit via **From URL** / `fetch_public_data` instead (e.g. the RCSB or
> EBI download URL). This gap is tracked in Appendix E.

> **Pitfall — the resolver's tool description over-promises slightly.** The MCP `resolve_accession`
> description says "GEO, SRA, ENA, DDBJ" (`backend/lib/mcp/tools_manifest.py:376-399`) — accurate. But a
> second, **legacy** `/api/accession/resolve` handler further down the file
> (`routes.ts:16771-16835`) also has PDB/EMDB branches; it is **shadowed** — Express serves the
> first-registered handler (line 8532) for that path, so those PDB/EMDB branches never run. Don't rely
> on them.

## How an accession flows into a run

The resolver does not download anything by itself — it *classifies and hands off*:

1. **Resolve.** `resolve_accession(accession)` returns `{workflow_id, workflow_name, nextflow_path,
   prefilled_params, ready_to_run: true, next_step}` (`routes.ts:8610-8621`). For `GSE…` that's Geo Data
   Connector with `{accession: "GSE…"}`; for `SRR…`/`PRJNA…` it's nf-core/fetchngs with `{input: "…"}`.
2. **Run.** You (or the agent) launch the resolved workflow with those pre-filled params (see I.6). The
   fetch happens *inside* the workflow on AWS Batch — GEOquery for GEO, fetchngs for SRA/ENA/DDBJ.
3. **Downstream.** The fetched artifact (count matrix, or FASTQ in S3) becomes the input to your actual
   analysis chain (II.1). The MCP tool description spells the sequence out: resolve → `run_workflow`.

For a file you can already point at, there are two direct staging paths that bypass accession
classification entirely:

- **`fetch_public_data`** (`browse_data` first to find the path) — server-side staging from a public
  source into S3. The backend maps `source_id` to a host —
  `ebi_ftp`→`ftp.ebi.ac.uk`, `ncbi_ftp`→`ftp.ncbi.nlm.nih.gov`, `ensembl_ftp`→`ftp.ensembl.org`,
  `ucsc_downloads`→`hgdownload.soe.ucsc.edu`, and `http_public` for a full HTTPS/FTP URL
  (`nextflow_executor.py:10208-10223`) — downloads it, uploads to the work bucket, and returns
  `{s3_uri, presigned_url, filename, size_bytes}` (`nextflow_executor.py:10186-10274`; frontend proxy
  `routes.ts:8692-8712`). Use the `s3://…` URI as a workflow input.
- **Composer → data browser → From URL** — the UI path. In the composer's Galaxy dataset browser,
  the **From URL** tab (`galaxy-dataset-browser.tsx:585`) posts your HTTPS/FTP/S3 URL or S3 prefix to
  `/api/datasets/import-url` (`galaxy-dataset-browser.tsx:439`; handler `routes.ts:3599`). The file
  becomes a first-class dataset object (see I.5) you can attach to any run. For data already on S3/HTTP
  this is "no transfer at all" — it registers the location rather than re-uploading
  (`galaxy-dataset-browser.tsx:185`).

## Tools behind this (agent/MCP surface)

| Tool | What it does | Backend |
|---|---|---|
| **`resolve_accession`** | Classify a GEO/SRA/ENA/DDBJ accession → best fetch workflow + pre-filled param | `/api/accession/resolve` (`routes.ts:8532`) |
| **`browse_data`** | List files/dirs at a path within a public source or an S3 workspace | `/api/data/browse` + `/api/s3/browse` (`routes.ts:8665, 8716`; `tools_manifest.py:400-433`) |
| **`fetch_public_data`** | Download a public file into BioMate S3; return S3 URI + presigned URL | `/api/data/fetch` → `/api/nextflow/fetch_public_data` (`routes.ts:8692`; `nextflow_executor.py:10186`) |

`browse_data` public sources are `ebi_ftp`, `ncbi_ftp`, `ensembl_ftp`, `ucsc_downloads`, `http_public`,
plus the S3 sources `biomate_workspace` and `user_s3`; the frontend routes the S3 sources to
`/api/s3/browse` and the rest to Galaxy's `remote_files` proxy (`routes.ts:892-896`).

## What's not covered

- **Structure & proteomics/metabolomics archives as *resolvable* accessions** — PDB, EMDB, PRIDE
  (PXD), MassIVE (MSV) are detected for input-validation but have **no resolver**; fetch them by URL
  instead. → Appendix E.
- **dbGaP / controlled-access archives** — not referenced in the resolver at all (no handler, no
  credentialed fetch). → Appendix E.
- **Identifier lookups that aren't datasets** — UniProt, RefSeq, Ensembl gene IDs, ChEMBL, PubChem,
  dbSNP, ClinVar are recognised as *identifiers* for validation, not fetched as files by the resolver.
  → Appendix E.
- **A dedicated ArrayExpress fetcher** — `E-MTAB-…`/`E-GEOD-…` route through nf-core/fetchngs (which can
  reach them via EBI) rather than an ArrayExpress-specific workflow; there is no archive-type branch for
  them. Documented as-is.

---
_Verification: coverage-ledger.md "## II.2 Public datasets & accession resolver" — all tier C
(source-read); no Batch fetch runs fired._
