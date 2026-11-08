# Appendix B — File Formats: Inputs Accepted & Output Viewers

This appendix lists the file formats BioMate accepts as **input** and the in-app **viewers** it uses to
render **outputs**. The output-viewer taxonomy is not aspirational — it is exactly the routing in the
production preview component:

> Source of truth: `frontend/client/src/components/step-output-preview.tsx`
> — `resolveViewer()` (lines ~90–106) maps a file extension to one of thirteen viewer kinds; the
> extension sets are declared at lines ~67–84.

A format that is not in one of these sets falls through to a **download** link (the honest default for
binary formats BioMate cannot render in the browser). No format is claimed to render unless it maps to a
real viewer below.

---

## 1. Output viewers (by evidence type)

Each output file is routed to a viewer by its extension. The kinds below are the `ViewerKind` union in
`step-output-preview.tsx` (lines ~86–88), in taxonomy order.

| Viewer kind | Renders | Extensions (from source) | What you see |
|---|---|---|---|
| **image** | Raster figures | `png`, `jpg`, `jpeg`, `gif`, `svg` | `<img>` with click-to-zoom lightbox |
| **pdf** | Vector figures (the dominant Bioconductor `pdf()` / `ggsave` output) | `pdf` | Native browser PDF embed (an `<iframe>`/`<embed>`, **not** an `<img>`) |
| **table** | Tabular data | `csv`, `tsv`, `json`, `tabular`, `star` | `InlineTableViewer` — handles CSV/TSV/JSON plus STAR/RELION column format; preview + download |
| **sequence** | Sequences | `fasta`, `fa`, `fastq`, `fq` | FASTA/FASTQ record list |
| **vcf** | Called variants | `vcf`, `bcf` | Variant table |
| **annotation** | Genome intervals | `bed`, `gff`, `gtf`, `gff3` | BED/GFF interval table |
| **structure** | 3D molecular structures | `pdb`, `mmcif`, `cif` | 3Dmol.js viewer — cartoon + spectrum default; **pLDDT coloring** for predicted structures |
| **density** | Volumetric maps | `mrc`, `map`, `mrcs`, `rec` | `DensityMapViewer` — full 3-axis slice viewer |
| **r-object** | Serialized R objects | `rds`, `rdata` | Binary — not browser-renderable; opens in RStudio (where provisioned) |
| **singlecell** | AnnData / single-cell | `h5ad`, `loom`, `h5` | `SingleCellSummaryPanel` (in-app UMAP / cluster / marker panel from a `<h5ad>.summary.json` sidecar); or CellxGene where provisioned |
| **html** | Self-contained reports (e.g. MultiQC) | `html`, `htm` | Sandboxed `<iframe>` |
| **text** | Logs & scripts | `log`, `txt`, `sh`, `py`, `out`, `err` | `<pre>` block with tail toggle |
| **download** | Everything else, incl. CryoSPARC binaries | `cs`, `csg`, and any unmatched extension | Download link only (honest — no fake render) |

### Domain-specific chart sidecars

Beyond the raw-file viewers above, `step-output-preview.tsx` mounts purpose-built charts when a run
emits the matching JSON sidecar (source: same file, viewer imports at lines ~23–32):

- **FSC curve** (`FscCurveChart`) — cryo-EM resolution curve.
- **Motion histogram** (`MotionHistogramChart`) — cryo-EM per-frame motion.
- **CTF quality** (`CtfQualityChart`) — cryo-EM CTF fit.
- **pLDDT chart** (`PlddtChart`) — AlphaFold per-residue confidence.
- **Sequence tracks** (`SeqTracks`) — annotated sequence intervals / flagged regions.
- **Hit grid** (`HitGrid`) — small-molecule design hits with verdicts.
- **Single-cell summary** (`SingleCellSummaryPanel`) — UMAP + clusters + markers.

These are data-gated: they appear only when the pipeline produced the sidecar, and fail soft to the
base viewer (or an honest empty state) when it did not.

---

## 2. Input formats accepted

Inputs enter BioMate two ways: **upload/ingest** (your files) and **accession resolve / fetch** (public
data). See Module I.5 (Files & the dataset object), Module I.2 (Composer), and Data II.2 (accession
resolver) for the full flows.

### 2a. Uploaded / attached files

Attach via the paperclip (OS picker + drag-drop) or the database icon (session / project / history / URL
import; chunked upload to 50 GB). Source: `frontend/client/src/components/chat-input.tsx` (~729–757) and
`galaxy-dataset-browser.tsx` (~428–525). Files are quality-profiled on ingest (Module I.5).

Common accepted inputs, by domain (the ingest side is format-permissive; these are the formats the
documented pipelines consume):

| Domain | Typical input formats |
|---|---|
| Transcriptomics (bulk) | `fastq`/`fq` (raw reads), `csv`/`tsv` count matrix, sample sheet CSV |
| Single-cell | `fastq`/`fq`, `h5`, `h5ad`, `loom` |
| Variant calling | `fastq`/`fq`, `bam`/`cram`, reference `fasta`, `vcf`/`bcf` (for annotation entry) |
| Cryo-EM | `mrc`/`mrcs`/`tif(f)` movies/micrographs, `star` (RELION metadata) |
| Structural biology | protein `fasta` (for prediction), `pdb`/`cif` (for docking/analysis), ligand SMILES/SDF |
| Drug discovery / ADMET | SMILES lists (`csv`/`smi`/inline), `sdf` |
| Proteomics | vendor MS files / `mzML`, `fasta` (search database) |
| Metabolomics | `mzML`/`mzXML`, vendor LC-MS files |
| Metagenomics | `fastq`/`fq` |

> Note on quality profiling: FASTQ with mean Phred < 20 is flagged **Watch**; an unreadable file is
> flagged **Blocked** (Module I.5, `data_perception.py`). This is advisory metadata, not a hard gate.

### 2b. Public data by accession

`resolve_accession` (Data II.2; `tools_manifest.py`) identifies an accession and returns the fetch
workflow + pre-filled params:

- **Resolvable → fetch runs on Batch:** GEO (`GSE*`/`GSM*`/`GDS*`) → GEO Data Connector; SRA/ENA/DDBJ /
  BioProject / ArrayExpress (`SRR*`, `SRX*`, `SRP*`, `ERR*`, `ERP*`, `DRR*`, `PRJNA*`, `PRJEB*`,
  `E-MTAB-*`, `E-GEOD-*`) → `nf-core/fetchngs`.
- **From-URL import:** a hosted-data URL registers the file as a dataset object.

> **Honesty note (see Appendix E):** PDB / EMDB / EMPIAR / PRIDE / MassIVE and UniProt / Ensembl /
> ChEMBL / dbSNP / ClinVar accessions are **detected for validation only** — they are **not** currently
> resolvable to an auto-fetch (they return 422). Do not document these as one-click fetches.

---

## 3. How viewer selection is decided (for the curious)

`resolveViewer(ext)` lowercases and strips the leading dot, then checks the extension sets in this order
(source lines ~90–106): image → pdf → table → sequence → vcf → annotation → structure → density →
r-object → singlecell → (CryoSPARC binary → download) → html → text → **download** as the final fallback.
Because `download` is the terminal branch, an unrecognized format never breaks the UI — it always at
least offers the file for download.

---
*Cross-references: Module I.8 (Outputs, viewers & interactive panels), Data II.2 (accession resolver),
Appendix E (formats/accessions not yet resolvable).*
