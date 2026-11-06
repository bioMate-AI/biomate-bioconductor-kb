# K2 imports of existing cyclic-peptide / macrocycle resources — results (2026-10-29)

Run `k2import1_20261029` (spot c6i.large, `i-0e3b373801f3a228f`, about 4 minutes, nothing on the laptop), code `knowledge_scale/import_resources.py`, protocol amendment A2 of `20261031_ALLATOM_KNOWLEDGE_SCALE_PREREG.md` (committed before the run). Numbers below are read from `knowledge_scale/results/import_summary_k2import1.json` (committed copy of `s3://biomate-nextflow-work/cyclic_peptide/allatom/k2/k2import1_20261029/imports/import_summary.json`; canonical per-resource tables are on S3 as `*.canonical.jsonl.gz`). Evidence level: V (read from the committed file).

## 1. Fetch (every route in A2 worked)
23 of 23 files fetched, sizes and sha256 recorded in the summary's manifest (HTTP dates 2026-10-29 17:21-17:24 GMT). Parse: 22 tables read as CSV/XLSX; the CyclicPepedia 2D-structure zip was fetched and not unpacked (counted, not used). Parse failures: none at the file level.

## 2. Table statistics and InChIKey joins
Join keys: RDKit stereo-aware InChIKey (full 27-character key, "full") and its first block (connectivity only, "flat"). Reference tables: local CycPeptMPDB annotation table (`stratification/data/annotations.csv.gz`: 7,991 rows, 7,988 unique full keys, 3,214 unique flat keys) and the live CycPeptMPDB download (8,466 rows, 7,988 unique full keys).

| resource (table) | rows | with InChIKey | unique full keys | in local CycPeptMPDB (full / flat) |
|---|---|---|---|---|
| CycPeptMPDB live peptides | 8,466 | 8,466 | 7,988 | 8,466 / 8,466 (reference) |
| CREMP-CycPeptMPDB summary | 3,258 | 3,258 | 3,258 | 3,256 / 3,258 |
| SweMacrocycleDB (Overall) | 6,585 | 6,585 | 4,696 | 154 / 164 |
| Macrocycle-DB `All.csv` | 50,654 | 50,653 (1 empty SMILES) | 47,966 | 240 / 391 |
| Macrocycle-DB `PDB.csv` | 3,752 | 3,752 | 621 | 44 / 44 |
| Macrocycle-DB `clinical.csv` | 611 | 611 | 96 | 7 / 7 |
| Macrocycle-DB `FDA-approve_drug.csv` | 73 | 72 | 72 | 0 / 2 |
| Macrocycle-DB `Linker.csv` | 1,746 | 1,746 | 1,706 | 0 / 0 |
| CyclicPepedia `Peptide_structrure_info` | 8,751 | 7,040 (1,711 empty SMILES, 19.6%) | 6,617 | 53 / 117 |
| CyclicPepedia other 11 tables (basic info, sequence info, source, function, family, target, bioassay, Pubmed, Source, Function, Family, Target) | 71 to 8,753 each | none carry SMILES | not applicable | not joined in this phase |
| CycPeptMPDB monomers | 385 | 385 (fragment SMILES) | 383 | 0 / 0 (expected: monomers, not peptides) |

Reading:
- **The join works.** 3,256 of 3,258 CREMP-linked peptides (99.94%) and 3,258 of 3,258 on the flat key match the local table, which is the internal control for the InChIKey pipeline.
- **Overlap with CycPeptMPDB is small for every other resource** (SweMacrocycleDB 154 of 4,696 unique structures, 3.3%; Macrocycle-DB 240 of 47,966, 0.5%; CyclicPepedia 53 of 6,617, 0.8%). These resources therefore add chemistry and metadata that CycPeptMPDB does not have, and they cannot be used as an independent permeability check on the same peptides except for the 154 SweMacrocycleDB structures.
- **CyclicPepedia metadata** (sources, functions, families, targets, bioassays, references) is keyed by CyclicPepedia ids, not by structure; joining it to structures is the next import step and was not done here.

## 3. Differences between the papers and the live resources (read before citing counts)
| resource | paper / abstract | live resource on 2026-10-29 |
|---|---|---|
| CycPeptMPDB | 7,334 cyclic peptides | 8,466 rows, 7,988 unique stereo-aware structures; our local table: 7,991 rows, the same 7,988 structures. So the live and local tables hold the SAME structures; the row difference is repeated measurements |
| SweMacrocycleDB | 5,638 data points, 4,216 macrocycles | 6,585 rows, 4,696 unique structures |
| Macrocycle-DB | 45,525 macrocycles | `All.csv` 50,654 rows (47,966 unique structures); the site's API `overall-statistics` reports 18,969 macrocycles, 58,310 activities, 2,533 targets, 3,752 PDB structures. Three different counts for related quantities; what each counts (entries, activity rows, molecules) is not documented in the files checked |
| CyclicPepedia | 8,744 cyclic peptides | 8,751 structure rows, 7,040 with a SMILES |
Correction of amendment A2: A2 said the live CycPeptMPDB "has been updated since the paper" and that its source list contains entries absent from our 54 local source strings. The import shows the live and local tables contain the same unique structures; whether source strings differ was not checked here and A2's statement about the source list is withdrawn.

## 4. What was not done / limits
- No units were harmonised; assay values are kept raw. No scientific claim is made from the imports.
- The CREMP conformer archives (8.3 GB, 11.6 GB) and the Macrocycle-DB `SDF.zip` (377 MB) were not imported. Norine has no confirmed bulk route and was not imported.
- InChIKey join fails for structures whose SMILES RDKit cannot parse or that lack SMILES (CyclicPepedia 1,711 rows; Macrocycle-DB 2 rows); they are counted, not dropped from the canonical files.
- Licences were not audited per file beyond the CREMP records (CC BY 4.0).
- Version drift between papers and live resources means any count quoted from a paper abstract must be re-stated from the file used.

## 5. Next import steps (not started)
1. Join CyclicPepedia metadata tables to structures by their internal ids; extract natural-source and target annotations for the 53 to 117 peptides that overlap CycPeptMPDB.
2. Normalise SweMacrocycleDB assay values (PAMPA 3,985; Caco-2 1,808; MDCK 679) onto log Papp with an assay flag and mark the 154 structures shared with CycPeptMPDB for a cross-source consistency check.
3. Macrocycle-DB `PDB.csv` (3,752 rows, 621 unique structures): filter to peptidic ring systems and link to PDB ids for the target-structure topic.
