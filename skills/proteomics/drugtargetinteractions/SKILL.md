---
name: bioconductor-drugtargetinteractions
description: Provides utilities for identifying drug-target interactions for sets of small molecule or gene/protein identifiers. The required drug-target interaction information is obained from a local SQLite instance of the ChEMBL database. ChEMBL has been chosen for this purpose, because it provides one of the most comprehensive and best annotatated knowledge resources for drug-target information available in the public domain.
when_to_use: Use when: Drug-Target Interactions; Metabolomics data analysis (drugTargetInteractions); Proteomics quantification (drugTargetInteractions). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# drugTargetInteractions

## Workflows

### Standard Workflow

Provides utilities for identifying drug-target interactions for sets of small molecule or gene/protein identifiers. The required drug-target interaction information is obained from a local SQLite instance of the ChEMBL database. ChEMBL has been chosen for this purpose, because it provides one of the most comprehensive and best annotatated knowledge resources for drug-target information available in the public domain.

```r
library(drugTargetInteractions)
chembldb <- system.file("extdata", "chembl_sample.db", package="drugTargetInteractions")
resultsPath <- system.file("extdata", "results", package="drugTargetInteractions")
config <- genConfig(chemblDbPath=chembldb, resultsPath=resultsPath)
downloadUniChem(config=config)
cmpIdMapping(config=config)
queryBy <- list(molType="cmp", idType="chembl_id", ids=c("CHEMBL17", "CHEMBL19"))
qresult1 <- drugTargetAnnot(queryBy, config=config)
```
Input: A list containing query molecule/protein IDs and a configuration object. Output: A data.frame of drug-target annotations.

## When to Use
- Identify drug-target interactions for sets of small molecules or gene/protein identifiers using a local SQLite instance of the ChEMBL database.
- Retrieve UniProt IDs for Ensembl gene IDs using sequence similarity nearest neighbors (SSNNs) via `getUniprotIDs` or paralogs via `getParalogs`.
- Query bioactivity data for compounds or proteins using `drugTargetBioactivity`.

## When NOT to Use
- For high-throughput de novo molecular docking or 3D structure-based drug design, use packages like `Rcpi` or external tools.
- For querying online databases directly without a local SQLite copy of ChEMBL, use direct web API clients.

## Data Requirements
- A local SQLite instance of the ChEMBL database (e.g., `chembl_sample.db` for testing).
- Query identifiers formatted as a list with `molType` (e.g., "cmp", "protein", "gene"), `idType` (e.g., "chembl_id", "UniProt_ID", "ensembl_gene_id"), and a character vector of `ids`.

## Key Parameters
- **chemblDbPath** (NULL): Path to the local ChEMBL SQLite database file passed to `genConfig`.
- **resultsPath** (NULL): Path to the directory where results are stored, passed to `genConfig`.
- **taxId** (9606): Taxonomy ID for organism selection in `getUniprotIDs`.
- **kt** ("ENSEMBL"): Keytype of the input keys in `getUniprotIDs`.
- **seq_cluster** ("UNIREF90"): Sequence similarity level ("UNIREF100", "UNIREF90", "UNIREF50") in `getUniprotIDs`.
- **id_mapping** (c(chembl="chembl_id", pubchem="PubChem_ID", uniprot="UniProt_ID", drugbank="DrugBank_ID")): Mapping vector used in `getDrugTarget`.

## Best Practices
- Use `genConfig` to set up paths to the local ChEMBL SQLite database and output directories before running queries.
- Run `downloadUniChem` and `cmpIdMapping` to download and prepare compound identifier mapping tables.
- Use `getParalogs` instead of `getUniprotIDs` when faster execution and wider evolutionary distances are preferred.
- Combine ID mapping and drug-target annotation steps using the meta function `runDrugTarget_Annot_Bioassay`.

## Common Pitfalls
- Using the toy database `chembl_sample.db` for real analyses: replace the path in `genConfig` with the path to a full downloaded ChEMBL SQLite database.
- Slow execution of `getUniprotIDs`: set `chunksize=1` only when tracking query Ensembl gene ID information is strictly required, or use `getParalogs` as a faster alternative.
- Missing UniProt to Ensembl mappings in final tables: use `tapply` to collapse Ensembl IDs when mapping back to UniProt IDs.

## Alternatives
- `biomaRt` for general gene/protein annotation and paralog retrieval.
- `UniProt.ws` for direct web-based UniProt ID mapping.
- `ensembldb` for local genomic and protein feature mapping.

## Citations
- Wu et al. 2006, Nucleic Acids Res (The Universal Protein Resource)
- Gaulton et al. 2012, Nucleic Acids Res (ChEMBL database)
- Bento et al. 2014, Nucleic Acids Res (ChEMBL bioactivity database update)

## References
- Homepage: bioconductor.org/packages/drugTargetInteractions
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/drugTargetInteractions/inst/doc/drugTargetInteractions.html
