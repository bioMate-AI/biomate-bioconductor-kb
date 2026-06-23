# BioMate File Upload — Complete Reference

## Upload sources

| Source | How | Size limit | Best for |
|--------|-----|-----------|---------|
| **Local upload** (drag-and-drop or click) | "This session" tab → Upload file | **5 GB per file** | Small-to-medium files you have locally |
| **URL import** (HTTP / HTTPS / FTP / S3) | "From URL" tab | **No limit** — Galaxy downloads server-side | Large files, public datasets (SRA, ENA, EMPIAR), private S3 buckets |
| **BioMate history** | "BioMate history" tab | — | Reuse outputs from a prior workflow run |

---

## Accepted file formats

All of these pass the server-side filter (`routes.ts:1114`). The UI label only shows a short
subset — the full list is below.

### Sequencing reads
`.fastq` `.fastq.gz` `.fq` `.fq.gz`

### Alignment / mapping
`.bam` `.sam` `.cram`

### Reference / sequence
`.fasta` `.fa` `.fna` `.fas` `.faa` `.fap`

### Variant / annotation
`.vcf` `.vcf.gz` `.bed` `.gff` `.gtf`

### Tabular / metadata
`.csv` `.tsv` `.txt` `.tab` `.xlsx` `.xls`

### Single-cell
`.h5ad` `.h5` `.hdf5` `.loom`

### Cryo-EM / electron microscopy
`.mrc` `.mrcs` `.tif` `.tiff` `.eer` `.spi` `.dm4` `.map`

### Mass spectrometry
`.mzml` `.mzxml` `.mgf`

### Archives (bulk upload / folders)
`.zip` `.tar` `.tar.gz` `.tgz` `.gz`

### Notebooks / R objects
`.ipynb` `.rds` `.rda`

### Phylogenomics / alignment
`.nwk` `.newick` `.treefile` `.phy` `.phylip` `.aln` `.nxs` `.nexus` `.mldist` `.bionj` `.contree`

### Other
`.json` `.xml` `.log` `.model`

---

## Folders

**There is no folder picker.** The browser file input does not support `webkitdirectory`.

**Workarounds:**

1. **Zip the folder** — `.zip` and `.tar.gz` are accepted; upload the archive as a single file.
   The workflow will receive the archive path and can unpack it on the compute node.
   ```
   zip -r my_samples.zip samples/
   ```

2. **S3 URL import** — if your files are already in S3, paste the common prefix as an S3 URL.
   Galaxy fetches all objects under that prefix at workflow start time (deferred mode).
   ```
   s3://my-bucket/project/samples/
   ```

3. **Reference a directory path directly** — if BioMate has access to a mounted network share
   or local path on the server, you can type the path in the chat:
   ```
   My FASTQ files are in /mnt/data/project42/raw/
   ```
   BioMate will register it via `POST /api/datasets/register-path`.

---

## Many small files (e.g. 100 sample FASTQs)

**Upload limit:** No hard cap on the number of files uploaded to Galaxy/S3 storage.

**LLM reference cap:** Only the **32 most recent** dataset references are kept in the
conversation's context and passed to the AI. Older references are silently dropped (FIFO)
when you exceed 32. The files themselves remain in Galaxy/S3.

| Files | What to do |
|-------|-----------|
| ≤32 files | Upload individually or zip; attach normally |
| 33–100 files | Zip into one archive, or use an S3 prefix URL |
| >100 files | S3 prefix URL (deferred import); tell the AI the path prefix |

The `X / 32` counter in the chat input shows how many references you have used in this session.

---

## Size limits

| Scenario | Limit |
|----------|-------|
| Local upload per file | **5 GB** |
| URL / S3 import per file | **No limit** (Galaxy downloads server-side) |
| Session storage quota | **50 GB** (shown in upload dialog) |
| Dataset references visible to AI | **32** per conversation (FIFO) |
| Files per HTTP upload request | **1** (client batches 3 concurrent requests) |

---

## URL import modes (in `file-upload.tsx`)

| Mode | Behaviour | Use when |
|------|-----------|----------|
| **Deferred** (default) | Galaxy creates a reference only; downloads when the workflow first needs the file | Large files, data you are not sure you will use |
| **Immediate** | Galaxy downloads now; file available for preview before the workflow runs | Small files where you want to verify content first |

---

## Tips summary (shown in UI)

1. **Formats**: FASTQ, BAM, SAM, VCF, BED, CSV, TSV, FASTA, H5AD, MRC, ZIP, and 40+ more.
2. **Large files (>5 GB)**: Use URL Import → paste an HTTPS, FTP, or S3 URL. No upload needed.
3. **Folders**: Zip the folder first (`zip -r name.zip folder/`), then upload the `.zip`.
   Or paste an S3 prefix URL and BioMate will reference all files under it.
4. **Many files**: Attach up to 32 individual files per conversation. For more, zip them or use an S3 path.
5. **Reuse outputs**: "BioMate history" tab lets you pick outputs from any previous run as input to the next.
6. **Public datasets**: Paste NCBI SRA, EBI ENA, or EMPIAR URLs directly — BioMate fetches them for you.
