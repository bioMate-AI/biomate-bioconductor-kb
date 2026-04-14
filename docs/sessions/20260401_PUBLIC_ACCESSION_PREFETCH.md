# Public-Database Accession Pre-Step Implementation

**Date**: 2026-04-01  
**Branch**: integration/next-phase  
**File changed**: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`  
**Tests**: `backend/tests/test_accession_detection.py` — **41/41 PASS**

---

## Problem

When a user typed an SRA accession (e.g. `SRR628582`) in the chat, `ai_assistant.py` correctly extracted it and injected it as the `reads` parameter default.  But `nextflow_executor.py` treated it as a local file path:

```
_is_path_param("reads", "SRR628582") → True
Path("SRR628582").exists()            → False
→ HTTPException 422 "Input path(s) not found"
```

The `sra_accession=True` flag set by `_inject_sra_into_params()` was never consumed by the executor.

---

## Solution

### 1. Comprehensive accession registry (`_ACCESSION_REGISTRY`)

Replaced the narrow `_SRA_ACCESSION_RE` with a 20-entry registry covering all major life-science databases:

| Type | Examples | Handler |
|------|---------|---------|
| SRA run | SRR628582, ERR1234567, DRR123456 | `sequencing` |
| ENA/SRA project | ERP123456, SRP123456 | `sequencing` |
| BioProject | PRJNA12345, PRJEB12345 | `sequencing` |
| GEO series/sample | GSE12345, GSM123456 | `sequencing` |
| ArrayExpress | E-MTAB-1234, E-GEOD-5678 | `sequencing` |
| PDB | 4ZQK, 1ABC | `structure` |
| EMDB | EMD-1234 | `structure` |
| UniProt | P12345, Q9NR61 | `protein_seq` |
| NCBI RefSeq protein | NP_012345, XP_012345 | `protein_seq` |
| NCBI RefSeq nucleotide | NC_000001 | `genomic_ref` |
| Ensembl gene/transcript | ENSG…, ENST… | `genomic_ref` |
| Ensembl protein | ENSP… | `protein_seq` |
| PRIDE | PXD001234 | `proteomics` |
| MassIVE | MSV000079033 | `proteomics` |
| ChEMBL | CHEMBL25 | `chemical` |
| PubChem CID | CID2244 | `chemical` |
| dbSNP | rs1234567 | `annotation` |
| ClinVar | VCV000012345, RCV000012345 | `annotation` |

Key guards to prevent false positives:
- Length: 4–30 characters
- Must not start with `/`, `s3://`, `http`
- PDB pattern requires at least one letter in positions 2-4 (excludes pure-numeric strings like `1000`)
- UniProt uses the official [OPQ][0-9][A-Z0-9]{3}[0-9] format

### 2. `_classify_accession(value)` → `Optional[dict]`

Returns `{"label": str, "handler": str, "accession": str}` or `None`.

### 3. `_is_public_accession(value)` → `bool`

Convenience wrapper.

### 4. `_validate_input_paths()` fix

Added early `continue` for any param value that `_is_public_accession()` recognises:

```python
if _is_public_accession(str(value)):
    continue  # resolved by accession pre-step
```

### 5. Download handlers

| Handler type | Function | API used |
|---|---|---|
| `sequencing` | `_run_fetchngs_prefetch()` | nf-core/fetchngs (id=12704, already in DB) |
| `structure` | `_download_pdb_structure()` | RCSB `/download/{ID}.cif` or EMDB FTP |
| `protein_seq` | `_download_uniprot_fasta()` | UniProt REST / Ensembl REST / NCBI efetch |
| `genomic_ref` | `_download_genomic_ref()` | Ensembl REST / NCBI efetch |
| `chemical` | `_download_chemical_structure()` | ChEMBL API / PubChem PUG REST |
| `proteomics` | (logged, no auto-download) | PRIDE datasets are too large to auto-download |
| `annotation` | (informational only) | No file download for rs/ClinVar IDs |

`_resolve_accession_file()` dispatches to the right handler based on the `handler` field.

### 6. `_accession_chain_thread()`

Background thread that:
1. Batches all `sequencing` accessions into one fetchngs run (single samplesheet)
2. Downloads non-sequencing accessions individually
3. Substitutes resolved local paths back into the main Nextflow command
4. Launches main workflow via `subprocess.Popen` + `_stream_logs`

Status transitions: `fetching_accessions` → `running` (or `failed`).

### 7. `execute_nextflow()` changes

- Detects accession-valued params before `_validate_input_paths`
- If any found: registers run with `status="fetching_accessions"`, starts chain thread, returns immediately
- The response includes `accessions: {param_key: label}` so the frontend can show a download-in-progress banner
- Normal (no accession) path unchanged

---

## Test results

```
41/41 PASS  (backend/tests/test_accession_detection.py)

Coverage:
  - All 18 accession types: positive match
  - PDB not-all-digits guard
  - Local paths, S3 URLs, HTTP URLs: not matched
  - Short strings, common param values (true/false/null): not matched
  - Gene symbols (BRCA1, TP53): not matched
  - _validate_input_paths: accessions skipped, real missing paths still raise 422
  - Accession values normalised to uppercase in returned dict
```

---

## Edge cases and limitations

1. **Multiple sequencing accessions** on different params (e.g. `reads1=SRR1`, `reads2=SRR2`) — both go into one fetchngs run; only the samplesheet path is substituted into the _first_ key matched. The samplesheet contains both samples.

2. **PRIDE datasets** are not auto-downloaded because raw MS files (Thermo .raw, Bruker .d) are often 10–100 GB. The user receives a URL instead.

3. **Annotation IDs** (rs, ClinVar) are passed through unchanged since most variant-calling pipelines accept them as lookup keys, not file paths.

4. **fetchngs failure** causes the whole chain to fail (status=`failed`). Non-sequencing download failures are logged as warnings and the original accession string is passed to the workflow (which may have its own retrieval logic).

5. **Proteomics accessions in a sequencing workflow** — unlikely but possible. The annotation path is taken (no download) and the workflow will likely fail with a clear error about missing files.
