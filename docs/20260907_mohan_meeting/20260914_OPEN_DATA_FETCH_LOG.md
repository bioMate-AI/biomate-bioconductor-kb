# Open Data Fetch Log — Mohan Collaboration (Lupus)

**Date:** 2026-09-14
**Operator:** automated acquisition agent
**Landing zone:** `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions/mohan_collab/{ACC}/`
**Scope:** OPENLY accessible lupus datasets only. Controlled-access resources (dbGaP phs001457, phs002812, EGA EGAS00001003662) and on-request resources were NOT attempted — those are applications, not downloads.

## Environment constraint encountered
The local disk was critically tight throughout the run (root volume dropped from ~3.3 GB to ~150 MB free due to external system activity, not this job). Mitigation: **all transfers were streamed `curl -> tee(sha256) -> aws s3 cp -`**, writing NO local intermediate file. sha256 was computed inline on the byte stream. This bypassed the disk constraint entirely for every landed file. Anything >2 GB was size-gated (HEAD-checked) and logged as "needs staging" rather than streamed.

---

## Summary table

| Priority | Accession | Status | Bytes landed | S3 path |
|---|---|---|---|---|
| 1 | ImmPort SDY997 | already-in-S3 | 0 (already held) | `.../immport/studies/SDY997/` |
| 2 | PRIDE PXD031069 | fetched (processed .msf) | ~1.22 GB (4 files) | `.../acquisitions/mohan_collab/PXD031069/` |
| 3 | GEO GSE174188 | metadata-fetched + expression needs-staging | ~24 KB metadata | `.../acquisitions/mohan_collab/GSE174188/` |
| 4 | GEO GSE10325 / GDS4185 | fetched | ~243.1 MB | `.../acquisitions/mohan_collab/GSE10325/` + `/GDS4185/` |
| 5 | GEO GSE72535 | fetched | ~35.8 MB | `.../acquisitions/mohan_collab/GSE72535/` |

---

## 1. ImmPort SDY997 — ALREADY IN OUR S3 (not re-downloaded)

**Status:** already-in-S3. We hold full ImmPort DR66; SDY997 was already present. NOT re-downloaded.

**S3 location:** `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/immport/studies/SDY997/`

**Inventory (13 objects, 15,537,657 bytes total):**
```
    7599942  07102016_AMP_SLE_Lab_Manual_revisedMP MS (1).PTL8530.pdf
     523538  AMP CyTOF reagent list.PTL10041.pdf
    1198988  AMP Lupus Phase I Clinical Protocol CLEAN 772016.PTL8529.pdf
     465688  AMP PBMC CyTOF IC Stain with Barcoding.PTL10042.pdf
     395867  AMP Renal Tissue draft SOP_CCB_21Sept2016.PTL10044.pdf
    1695363  AMP SLE Form Packet (v2015-09-21).pdf
     226006  AMP SLE Phase1 Final Sorting Plan.PTL10046.pdf
    2934887  AMP Single Cell HTSEQ.PTL10045.pdf
     467659  AMP Total Leukocyte (TL) CyTOF IC Stain with Barcoding.PTL10048.pdf
       2554  SDY997.29Jan2019.DataCurationNotes.txt
       2877  SDY997.April2019.DataCurationNotes.txt
      23040  SDY997_Data_Curation_Notes.doc
       1248  StudyFile.Obsolete.Period.StudyGlossary.ID4633-34.5290.SDY997.txt
```

**IMPORTANT caveat:** what we hold under SDY997 in S3 is the **protocol / SOP / clinical-form / curation-notes document set** — NOT the SDY997 primary data matrices (the ALCAM urine-proteomics tables, AMP renal CyTOF/scRNA expression). Those primary-data files require an authenticated ImmPort bulk pull (DR66 file archive), which was not forced per instructions. If the ALCAM urine-proteomics quantitative tables are specifically needed, an authenticated ImmPort download of the SDY997 result files is required.

---

## 2. PRIDE PXD031069 — FETCHED (processed results; raw skipped)

**Study:** "Discovery of Novel Circulating Immune Complexes in Lupus Nephritis Using Immunoproteomics" (Mohan lab). Protein A/G + C1q capture of serum immune complexes in LN vs HC, LC-MS/MS.

**Status:** fetched. The 4 processed **Proteome Discoverer `.msf` result files** (SEARCH category) were streamed to S3. The 4 large **`.raw`** instrument files (RAW category, ~0.86–1.09 GB each, ~3.89 GB total) were **skipped** per instructions (huge raw).

**S3 location:** `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions/mohan_collab/PXD031069/`

**Fetched files (processed .msf, source sizes):**
```
  311078912  C1Q_HC.msf
  317313024  C1Q_LN.msf
  299835392  Protein_AG_HC.msf
  291405824  Protein_AG_LN.msf
  --------------------------------
 1219633152  total (~1.22 GB)
```

**Skipped (raw, not landed):**
```
  910961818  C1Q_HC.raw
 1088044858  C1Q_LN.raw
  863596126  Protein_AG_HC.raw
 1023639746  Protein_AG_LN.raw
```
Source URL pattern: `https://ftp.pride.ebi.ac.uk/pride/data/archive/2022/05/PXD031069/{file}`

sha256 hashes: see PXD031069 section of the JSON log (computed inline during streaming).

---

## 3. GEO GSE174188 — METADATA FETCHED; EXPRESSION MATRIX NEEDS STAGING

**Study:** Perez et al. 2022, *Science* (DOI 10.1126/science.abf1970), "Single-cell RNA-seq reveals the cell-type-specific molecular and genetic associations to lupus." Multiplexed scRNA-seq of **1,263,676 PBMCs** from adult lupus samples.

**KEY FINDING (corrects the task premise):** GSE174188 does **NOT** host an open expression matrix. The GEO record explicitly states: *"The raw data and processed data will be made available in dbGaP through controlled access due to patient privacy concerns,"* and every sample's `supplementary_file = NONE`. The GEO FTP tree contains only `matrix/`, `miniml/`, `soft/` — there is **no `suppl/` directory**. So GEO holds metadata only; the primary data is controlled (dbGaP phs002812).

**Open expression data IS available elsewhere — at CZ CELLxGENE (fully processed, open):**
- Collection: `436154da-bcf1-4130-9c8b-120ff9a888f2`
- Dataset: `218acb0f-9f2f-4f76-b90b-15a4b7c7f629` — "multiplexed scRNA-seq of 1.2 million PBMCs from adult lupus samples", 1,263,676 cells
- **H5AD URL:** `https://datasets.cellxgene.cziscience.com/c55dc602-d168-4d15-acc1-5de4f2f5d551.h5ad`
- **Size: 12,218,105,530 bytes (~11.38 GB)** — HEAD 200, supports byte-range.
- **STATUS: needs-staging on a bigger node.** Exceeds the 2 GB size-gate; cannot fit local disk and is too large to stream reliably here. Fetch on a node with ≥15 GB scratch (or multipart byte-range straight to S3).

**Landed (open GEO metadata only):**
`s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions/mohan_collab/GSE174188/`
```
       7030  GSE174188_series_matrix.txt.gz
       8110  GSE174188_family.soft.gz
       8546  GSE174188_family.xml.tgz
```

---

## 4. GEO GSE10325 / GDS4185 — FETCHED

**Study:** "Expression data from human peripheral blood subsets" — SLE PBMC subsets (B / T / myeloid), microarray. GDS4185 is the curated GEO DataSet derived from GSE10325.

**S3 location:** `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions/mohan_collab/GSE10325/` and `/GDS4185/`

**Landed files:**
```
  236769280  GSE10325/GSE10325_RAW.tar
    3109393  GSE10325/GSE10325_series_matrix.txt.gz
       3657  GSE10325/filelist.txt
    3212908  GDS4185/GDS4185.soft.gz
  --------------------------------
  243095238  total (~243.1 MB)
```

---

## 5. GEO GSE72535 — FETCHED

**Study:** Discoid lupus erythematosus (DLE) skin expression profiling, microarray.

**S3 location:** `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions/mohan_collab/GSE72535/`

**Landed files:**
```
   27443200  GSE72535_RAW.tar
    5054009  GSE72535_non-normalized.txt.gz
    3257257  GSE72535_series_matrix.txt.gz
        260  filelist.txt
  --------------------------------
   35754726  total (~35.8 MB)
```

---

## NOT attempted (controlled / on-request — applications, not downloads)
- **dbGaP phs001457** (AMP SLE genotype/controlled) — controlled access.
- **dbGaP phs002812** (Perez SLE genotype + controlled raw/processed for GSE174188) — controlled access.
- **EGA EGAS00001003662** — controlled access.

---

## Totals landed this run (excludes already-held SDY997)
- PXD031069 processed .msf: 1,219,633,152 bytes
- GSE10325 + GDS4185: 243,095,238 bytes
- GSE72535: 35,754,726 bytes
- GSE174188 metadata: 23,686 bytes
- **TOTAL newly landed: ~1,498,506,802 bytes (~1.50 GB)**

## Needs staging on a bigger node
- GSE174188 / Perez lupus H5AD (CELLxGENE): 12,218,105,530 bytes (~11.38 GB) — open URL recorded above.
- (optionally) PXD031069 four `.raw` files: 3,886,242,548 bytes (~3.89 GB) — intentionally skipped as huge raw.
