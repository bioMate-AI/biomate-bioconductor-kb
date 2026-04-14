# Using Public Database IDs in BioMate Chat

**Date:** 2026-04-12

---

## What this does

If your data is already in a public database (NCBI SRA, GEO, PDB, EMDB), you can type the accession ID directly in your message instead of uploading a file.

BioMate detects the ID, looks up the public download URL, and tells the AI what that URL is — so the AI can fill in the right workflow input parameter automatically. The workflow executor then fetches the file at run time; nothing is downloaded to BioMate servers.

---

## Supported databases (as of 2026-04-12)

| Database | ID formats | What the AI receives |
|----------|-----------|----------------------|
| NCBI SRA — sequencing runs | `SRR123456`, `ERR030872`, `DRR012345` | FTP FASTQ path |
| NCBI SRA — studies | `SRP012345`, `ERP004736` | SRA study URL |
| NCBI GEO | `GSE12345`, `GSM123456` | GEO accession page |
| Protein Data Bank | `PDB:1ABC` or `PDB 2HHB` | mmCIF/PDB download URL |
| EMDB (cryo-EM maps) | `EMD-1234` or `EMDB-1234` | `.map.gz` download URL |

**For any other database:** paste the direct download URL (HTTP, FTP, or S3) in your message. The AI will use it the same way.

---

## What it does NOT do

- It does **not** download the file to BioMate. The Nextflow workflow fetches it at run time.
- It does **not** guarantee the correct parameter mapping for every possible workflow. The AI infers the target parameter from context (e.g. "dock my ligand against PDB:6LU7" → `receptor` parameter). If the AI picks the wrong parameter, you can correct it in the parameter panel before running.
- It does **not** handle a file containing a list of IDs. If you have multiple accessions, list them in the message: *"process runs SRR001, SRR002, SRR003"*. The AI will see all three resolved URLs. Whether the workflow supports multiple inputs depends on the specific workflow.
- It does **not** support batch download or pre-fetching. Data is pulled only when the workflow runs.

---

## Examples

> *"Run quality control and alignment on SRR1518169 with the human hg38 reference"*

> *"Dock compound CHEMBL123 against PDB:6LU7 — use the REINVENT pipeline"*

> *"Process the cryo-EM dataset EMD-2984 through the CryoSPARC standard SPA workflow"*

> *"Analyse differential expression for GEO study GSE12345, treated vs. control"*

---

## When the ID is not recognised

The chip under the input shows **"not recognised"** with a tooltip. This means either:
1. The accession format is from a database not in the supported list above — paste the direct download URL instead.
2. The ID has a typo.

BioMate still sends your message; the unresolved ID is passed as plain text and the AI may still interpret it correctly if the database is well-known.
