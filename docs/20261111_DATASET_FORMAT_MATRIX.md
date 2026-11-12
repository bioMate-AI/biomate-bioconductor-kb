# Dataset panel format matrix — baseline on dev (2026-11-11)

**What this is.** A live E2E measurement of what BioMate's dataset panel (Data → project Files → open a
file) shows for 28 common bioinformatics formats and two folder uploads. It is the BASELINE before the
format work deploys. Harness: `frontend/e2e/dataset-format-matrix.e2e.ts`; raw results:
`frontend/e2e/format-matrix-results.json`; screenshots: `frontend/e2e/screenshots/format-matrix/<key>.png`
(full view) and `<key>.qc.png` (QC card). Screenshots are gitignored (`frontend/e2e/screenshots/`) and are regenerated on every run.

- **Target:** https://dev-public.biomate.ai, `build-info.json` commit **`eeb1219cd0382edcb57fb1e6a58522cdda308fc2`**
  (checked before and after the run; an earlier attempt at ~02:23Z saw `ebd63e6c…`, so dev was redeployed
  between attempts — see "Harness notes").
- **Run:** 2026-11-12T02:25Z → 02:29Z UTC, 1 passed (4.3 min). One login, one project (deleted at the end),
  fixture account, no response stubbing.
- **Inputs:** real fixtures from Galaxy's datatype tests (`backend/lib/galaxy/datatypes/test/`), plus a
  header-less gene list, a narrowPeak, and the folders `pairs/` and `tenx/` written by the harness.
- **Every file opened and settled** (5–11 s each); no page errors and no visible error banners.

## Verdict rules

- **PASS** — a format-appropriate preview (correct columns/records/viewer) and a QC card that describes the file correctly.
- **PARTIAL** — something useful is shown, but the preview or the QC is wrong in a way a user would notice
  (header-less file shown with its first data row as the header, wrong record parsing, QC that
  contradicts the preview, internal temp filenames shown, spurious QC findings).
- **FAIL** — no content preview ("Content preview is not available for this format") or a blank viewer, and/or QC
  that blocks or cannot read the file.

## Summary

| Verdict | Count | Formats |
|---|---|---|
| PASS | 3 | VCF, MRC, JSON |
| PARTIAL | 13 | CSV, TSV, BED, BED12, GTF, GFF3, FASTA, FASTQ, SMILES, PDB, gene list, narrowPeak, 10x features.tsv / barcodes.tsv (counted once) |
| FAIL | 14 | FASTA.gz, FASTQ.gz, VCF.gz (bgzip), BAM, CRAM, h5ad, loom, XLSX, MTX, SDF, CIF, TIFF, POD5, folder-level recognition (pairs / 10x) |

**Main gaps, by cause:**

1. **No gzip/bgzip decode in the preview.** `.fasta.gz`, `.fastq.gz`, `.vcf.gz` show "Content preview is not
   available for this format", but the profiler *does* read them for FASTQ.gz / VCF.gz (QC shows reads / 30
   variants). The preview and the QC disagree.
2. **Header-less tables use the first data row as the header.** This affects TSV (`2.tabular`), BED, BED12, GTF,
   narrowPeak, SMILES, gene list, barcodes.tsv and features.tsv. The rows table shows `chr1 | 147962192 | …` as
   column names, and a 2-line BED12 shows as "1 row". GFF3 and VCF get correct column names because they go
   through the rich text viewer instead of the rows table.
3. **PDB goes to the rows table instead of the 3D viewer.** The rows endpoint claims `.pdb` first, so the
   structure viewer is never reached. The table is split on whitespace (`HEADER DE NOVO PROTEIN` |
   `MEMBRANE PROTEIN 09-OCT-15 5E5Z`).
4. **The FASTQ viewer parses FASTQ as FASTA.** The quality line is shown as its own ">" record (0 bp), and the
   second read's sequence and quality are joined (68 bp). The stat grid says "COLUMNS 34" (it is the read length).
5. **There is no preview path for binary or container formats:** BAM, CRAM, h5ad, loom, XLSX, POD5, TIFF (the
   image regex is png/jpg/gif/webp/svg only), and MTX/SDF (text, but not in the preview's TEXT list).
6. **QC text problems:**
   - "This file type cannot be profiled (perception_XXXX.ext)" shows an **internal temp filename**
     (GFF3, FASTA, FASTA.gz, CIF, MRC, h5ad, loom, XLSX, MTX, SDF, POD5).
   - BAM, CRAM and TIFF are **Blocked** with "The file could not be parsed: line contains NUL". A valid binary
     file is reported as broken.
   - FASTA QC says SEQUENCES 0 / LENGTH 0 while the viewer shows a 21,618 bp record.
   - CSV/GTF/BED QC treat the first or last column as a "class label" (e.g. 2.csv: "Column z … perfectly
     predicts the label — a leaked identifier"; BED12: "12 columns near-constant", which is an artefact of the
     wrong header).
7. **Folders are only shown as folders.** `pairs/` (S1_R1, S1_R2, orphan S2_R1) and `tenx/` (matrix.mtx,
   barcodes.tsv, features.tsv) render as plain folders with counts of 3. Nothing groups R1/R2, flags the
   orphan S2_R1, or recognises a 10x matrix bundle. `tenx/matrix.mtx` has no quality dot.

## Per-format matrix

| Format (fixture → uploaded as) | Preview shown | QC card | Verdict | Reason |
|---|---|---|---|---|
| CSV (`2.csv`) | Rows table, columns `x, y, z`, 49 rows | Watch — "Class '1' is only 14%…", "Column 'z' … perfectly predicts the label — a leaked identifier" | PARTIAL | Preview correct; QC invents a label (x) and calls a continuous column a leaked ID |
| TSV (`2.tabular` → `2.tsv`) | Rows table, columns `1, 68, 4.1`, 9 rows | Good | PARTIAL | Header-less: the first data row is used as the header (10 rows → 9) |
| BED6 (`1.bed`) | Rows table, columns `chr1, 147962192, 147962580, CCDS989.1_…, 0, -` | Watch — "1 column near-constant: 0" | PARTIAL | No BED column names; the first interval becomes the header |
| BED12 (`complete.bed`) | Rows table, 12 columns named from the first line, **1 row** | Watch — "12 columns near-constant" | PARTIAL | 2-line file shown as 1 row; QC finding is an artefact of the wrong header |
| GTF (`grch37.75.gtf`) | Rows table, 9 columns named from the first record (`chr1, pseudogene, gene, 11869, …`) | Watch — near-constant columns; attribute string treated as a class | PARTIAL | No GTF column names; attributes not parsed |
| GFF3 (`gff.gff3`) | Annotation table viewer: `seqname, source, feature, start, end, score, strand, frame, attribute`, "145 rows × 9 cols, showing first 100" | Watch — "cannot be profiled (perception_ei71u5jq.gff3)"; ROWS 0 / COLUMNS 0 | PARTIAL | Preview good; QC cannot read it, shows a temp filename, and stats are "—" |
| FASTA (`1.fasta`) | Sequence viewer: `>hg17`, 21,618 bp | Watch — SEQUENCES 0, LENGTH 0, "cannot be profiled (perception_….fasta)" | PARTIAL | Preview good; QC contradicts it (0 sequences) |
| FASTA.gz (`1.fasta.gz`) | "Content preview is not available for this format." | Watch — "cannot be profiled (perception_….gz)" | FAIL | No gzip decode in preview or QC |
| FASTQ (`1.fastqsanger` → `1.fastq`) | Sequence viewer, parsed **as FASTA**: quality line shown as a ">" record (0 bp), read 2 seq+qual joined (68 bp) | Good — READS 2, READ LENGTH 34, mean Phred 21.5, "single-end unless mate present" | PARTIAL | QC correct; preview mis-parses FASTQ; stat grid "COLUMNS 34" |
| FASTQ.gz (`1.fastqsanger.gz` → `1.fastq.gz`) | "Content preview is not available…" | Good — reads profiled (ROWS 2 / COLUMNS 34 in the stat grid) | FAIL | QC decodes the gzip but the preview does not |
| VCF (`1.vcf`) | Variant table viewer: `CHROM POS ID REF ALT QUAL FILTER INFO FORMAT wgs2`, 30 rows × 10 cols | Good — "30 variant records across 1 sample(s)", plan impact | PASS | Minor: QC/stat grid show "COLUMNS 1" |
| VCF.gz bgzip (`1.vcf_bgzip` → `1.vcf.gz`) | "Content preview is not available…" | Good — 30 variants | FAIL | QC reads it; preview does not decode bgzip |
| BAM (`1.bam`) | "Content preview is not available…" | **Blocked** — "The file could not be parsed: line contains NUL" | FAIL | No alignment summary; a valid BAM is reported as broken |
| CRAM (`2.cram`) | "Content preview is not available…" | **Blocked** — "line contains NUL" | FAIL | Same as BAM |
| h5ad (`pbmc3k_tiny.h5ad`) | "Content preview is not available…" | Watch — "cannot be profiled (perception_….h5ad)" | FAIL | No AnnData summary |
| Loom (`test.loom`) | "Content preview is not available…" | Watch — "cannot be profiled (perception_….loom)" | FAIL | No Loom summary |
| XLSX (`1.excel.xlsx` → `1.xlsx`) | "Content preview is not available…" | Watch — "cannot be profiled (perception_….xlsx)" | FAIL | No sheet reader (the tree even shows a table icon) |
| MTX (`1.mtx`) | "Content preview is not available…" | Watch — "cannot be profiled (perception_….mtx)" | FAIL | No sparse-matrix summary (5×5, 8 nnz) |
| SDF (`drugbank_drugs.sdf`) | "Content preview is not available…" | Watch — "cannot be profiled (perception_….sdf)" | FAIL | No molecule table or 2D depiction |
| SMILES (`drugbank_drugs.smi`) | Rows table, 2 columns named from the first record (Goserelin's SMILES + `Goserelin`), 1 row | Watch — "2 columns near-constant" | PARTIAL | Header-less: one of the 2 molecules is used as the header; no structure depiction |
| PDB (`5e5z.pdb`) | **Rows table** (whitespace-split records, 356 rows, header `HEADER DE NOVO PROTEIN` / `MEMBRANE PROTEIN 09-OCT-15 5E5Z`) | Watch — "1 column ≥50% missing" | PARTIAL | The 3D viewer exists but the rows table claims `.pdb` first |
| CIF (`Si.cif`) | 3D structure viewer (Cartoon/Stick/Sphere/Line), **canvas blank** | Watch — "cannot be profiled (perception_….cif)" | FAIL | Small-molecule/crystal CIF renders nothing in the default Cartoon style |
| MRC (`1.mrc`) | Density viewer: 5×4×1 voxels, XY/XZ/YZ planes, slice + contrast; slice is black | Watch — "cannot be profiled (perception_….mrc)" | PASS | Black is correct: the fixture's data and cell are all zero (checked from the header). QC temp-filename text is the shared issue |
| TIFF (`1.tiff`) | "Content preview is not available…" | **Blocked** — "line contains NUL" | FAIL | TIFF is not in the IMAGE list; a valid image is reported as broken |
| JSON (`1.json` = `[1]`) | JSON tree (`• 1`) | Watch — FORMAT JSON, ROOT array, VALUES 2, depth 1; "only structure checked" | PASS | Correct; "VALUES 2" for `[1]` counts the root |
| POD5 (`test.pod5`) | "Content preview is not available…" | Watch — "cannot be profiled (perception_….pod5)" | FAIL | No nanopore read summary |
| Gene list (inline, 12 genes, no header) | Rows table, header **`TP53`**, 11 rows | Good — "11 rows × 1 columns" | PARTIAL | First gene used as the header; the count is off by one |
| narrowPeak (inline, 5 peaks) | Rows table, 10 columns named from peak 1, 4 rows | Watch — "1 column near-constant: ." | PARTIAL | No narrowPeak column names; first peak used as the header |
| `tenx/features.tsv` (inline, 5 features) | Rows table, columns `ENSG00000243485, MIR1302-2HG, Gene Expression`, 4 rows | Watch — "near-constant: Gene Expression" | PARTIAL | Header-less: first feature used as the header |
| `tenx/barcodes.tsv` (inline, 5 barcodes) | Rows table, header `AAACATACAACCAC-1`, 4 rows | Good | PARTIAL | Header-less: first barcode used as the header |
| `tenx/matrix.mtx` (1.mtx + comment line) | "Content preview is not available…" | Watch — "cannot be profiled (perception_….mtx)" | FAIL | Same as MTX |
| `pairs/S1_R1`, `S1_R2`, `S2_R1` `.fastq.gz` (derived from 1.fastqsanger.gz) | "Content preview is not available…" (all three) | Good (reads profiled) | FAIL | Same as FASTQ.gz |

## Folders (tree view)

Screenshots: `folder-pairs.png`, `folder-tenx.png`.

| Folder | What the tree shows | Verdict | Reason |
|---|---|---|---|
| `pairs/` | `inputs ▸ pairs (3)`: S2_R1.fastq.gz, S1_R2.fastq.gz, S1_R1.fastq.gz (150 B each, green dots) | FAIL (recognition) / PASS (structure kept) | Folder structure is kept, but there is no R1/R2 pairing and the orphan S2_R1 is not flagged |
| `tenx/` | `inputs ▸ tenx (3)`: features.tsv (orange dot), barcodes.tsv (green), matrix.mtx (no dot) | FAIL (recognition) / PASS (structure kept) | Not recognised as a 10x matrix bundle (cells × genes); matrix.mtx is not profiled |

## Harness notes

- **Content-hash dedup:** uploads with identical bytes link to one entry (`project-routes.ts`). The folder copies
  are therefore made byte-distinct: FASTQ read headers are renamed per sample/mate, and an extra `%` comment line
  is added to `tenx/matrix.mtx`. The harness asserts that no upload was deduplicated.
- **Dev redeploy during the first attempt:** that attempt got an empty-body **502** on the 10th upload
  (`1.fastq.gz`). Uploading the same file in isolation with curl returned 201 (and 13 rapid uploads in a row all
  returned 201). `build-info` had changed from `ebd63e6c…` to `eeb1219c…`, so dev was being redeployed. The
  harness now retries a bare gateway 502/503/504 up to twice and records the attempts in
  `uploadAttempts`. The baseline run needed no retries.
- **Project cleanup:** the first attempt's project was not deleted, because its `finally` delete was swallowed
  during the redeploy. It was deleted by hand. The harness now retries the delete and logs a warning instead of
  failing silently.
- **Viewport:** 1920×1080 at 1x. Each file waits until no loading skeleton or status remains (≤75 s), plus 2.5 s
  for rich viewers to paint.
- **Preview-kind labels in the JSON:** `rows-table` = the paged rows table (column names in `columns`).
  `rich-table-viewer` = the VCF/annotation viewer (columns in `otherTableColumns`). `text-other` = the sequence
  viewer (FASTA/FASTQ). `message` = the "Content preview is not available" line. `structure-3d`, `density` and
  `json-tree` are the rich viewers.

## Next steps

Re-run the same harness after the format work deploys and compare it with this baseline:

```
cd frontend && E2E_FIXTURE_PASSWORD="$(cat ~/.config/biomate/e2e_fixture_password)" BIOMATE_URL=https://dev-public.biomate.ai \
  npx playwright test e2e/dataset-format-matrix.e2e.ts --project=chromium --reporter=line --retries=0
```
