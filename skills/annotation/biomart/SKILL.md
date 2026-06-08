---
name: bioconductor-biomart
description: In recent years a wealth of biological data has become available in public data repositories. Easy access to these valuable data resources and firm integration with data analysis is needed for comprehensive bioinformatics data analysis. bio
when_to_use: Use when: Convert between gene IDs (Ensembl → HGNC symbol → Entrez → RefSeq); Retrieve gene coordinates, GO terms, pathway annotations; Get protein sequences or transcript sequences; Cross-species homology / ortholog mapping
user-invocable: false
---

# biomaRt — Comprehensive Skill Guide

> **Domain:** Annotation / ID mapping
> **Bioconductor:** [biomaRt](https://bioconductor.org/packages/release/bioc/html/biomaRt.html)
> **Paper:** Durinck S et al. (2009). Nature Protocols, 4:1184-1191.

Query Ensembl BioMart databases to retrieve gene annotations, ID conversions, sequence retrieval, and cross-species homology information.

## When to Use

- Convert between gene IDs (Ensembl → HGNC symbol → Entrez → RefSeq)
- Retrieve gene coordinates, GO terms, pathway annotations
- Get protein sequences or transcript sequences
- Cross-species homology / ortholog mapping

**Alternatives:** `AnnotationDbi (OrgDb)`, `AnnotationHub`, `mygene (Python/R)`

## Do NOT Use When

- Offline environments — biomaRt requires internet access to Ensembl servers.
- Very large ID lists (>100K IDs) — consider AnnotationDbi local OrgDb instead for speed.
- Non-Ensembl databases without a BioMart interface.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Internet** | Required — queries Ensembl servers remotely |
| **Notes** | Cache results locally; pin Ensembl version for reproducibility |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("biomaRt")
library(biomaRt)
```

## Workflows

### Gene ID Conversion (Ensembl → HGNC Symbol → Entrez)
*Convert a list of Ensembl gene IDs to gene symbols and Entrez IDs*

#### Connect to Ensembl

```r
library(biomaRt)
ensembl <- useEnsembl(biomart="genes", dataset="hsapiens_gene_ensembl")
```

#### Check available attributes and filters

```r
# Find relevant attributes
listAttributes(ensembl)[grep("symbol|entrez|gene_id", listAttributes(ensembl)$name, ignore.case=TRUE), ]
```

#### Run ID conversion query

```r
my_ids <- c("ENSG00000139618", "ENSG00000141510", "ENSG00000157764")

id_map <- getBM(
    attributes = c("ensembl_gene_id", "hgnc_symbol", "entrezgene_id",
                   "chromosome_name", "gene_biotype"),
    filters    = "ensembl_gene_id",
    values     = my_ids,
    mart       = ensembl
)
head(id_map)
```

#### Get GO annotations

```r
go_annot <- getBM(
    attributes = c("ensembl_gene_id", "hgnc_symbol", "go_id",
                   "name_1006", "namespace_1003"),
    filters    = "ensembl_gene_id",
    values     = my_ids,
    mart       = ensembl
)
```

### Cross-Species Ortholog Mapping (Human → Mouse)
*Find mouse orthologs of human genes using getLDS*

#### Set up both marts

```r
human <- useEnsembl("genes", dataset="hsapiens_gene_ensembl")
mouse <- useEnsembl("genes", dataset="mmusculus_gene_ensembl")
```

#### Query orthologs with getLDS

```r
orthologs <- getLDS(
    attributes  = c("hgnc_symbol", "ensembl_gene_id"),
    filters     = "hgnc_symbol",
    values      = c("BRCA1", "TP53", "EGFR"),
    mart        = human,
    attributesL = c("mgi_symbol", "ensembl_gene_id"),
    martL       = mouse
)
head(orthologs)
```

## Key Functions & Parameters

### `useEnsembl()()`

Connect to an Ensembl BioMart database

| Parameter | Description |
|-----------|-------------|
| `biomart` | 'genes' (default) \| 'snps' \| 'regulation' \| 'mouse_strains' |
| `dataset` | species dataset e.g. 'hsapiens_gene_ensembl', 'mmusculus_gene_ensembl' |
| `version` | Ensembl release number (e.g. 110); NULL = current |
| `mirror` | 'useast' \| 'uswest' \| 'asia' \| 'www' (geographic mirror) |

### `getBM()()`

Submit a BioMart query to retrieve attributes filtered by values

| Parameter | Description |
|-----------|-------------|
| `attributes` | character vector of attributes to retrieve (see listAttributes()) |
| `filters` | filter name(s) to apply (see listFilters()) |
| `values` | values for the filter (e.g. vector of Ensembl IDs) |
| `mart` | Mart object from useEnsembl() |

### `listAttributes()()`

List all available attributes for a mart

| Parameter | Description |
|-----------|-------------|
| `mart` | Mart object |

### `listFilters()()`

List all available filters for a mart


### `listDatasets()()`

List all available datasets (species) in a BioMart


### `getLDS()()`

Linked dataset query — retrieve attributes from two datasets simultaneously (e.g. human-mouse orthologs)

| Parameter | Description |
|-----------|-------------|
| `attributes` | human attributes to retrieve |
| `filters` | filter to apply in first dataset |
| `values` | filter values |
| `mart` | first mart (e.g. human) |
| `attributesL` | attributes from linked dataset |
| `martL` | linked mart (e.g. mouse) |

## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Ensembl gene models represent the current canonical annotation (may differ from UCSC or RefSeq).
- Gene IDs are stable within an Ensembl release but can change between releases (use archived versions).

## Result Interpretation

- `getBM()` result: data.frame with one row per match; 1:many relationships possible (e.g. one gene → many GO terms).
- Missing values in output: gene ID not annotated for that attribute in Ensembl (not an error).
- Use `GENCODE` genome builds (GRCh38) for human; `GRCm39` for mouse.

## Best Practices

- Cache results locally — BioMart queries can be slow; save results with `write.csv()` or `saveRDS()`.
- Use `version=` argument to pin Ensembl release for reproducibility.
- Use `useEnsembl(mirror='useast')` if the default server is slow or down.
- For ID conversion from many IDs, use `getBM()` with `filters='ensembl_gene_id'` and `values=my_gene_ids`.
- Common attribute names: `ensembl_gene_id`, `hgnc_symbol`, `entrezgene_id`, `chromosome_name`, `start_position`, `gene_biotype`.
- For non-model organisms use `listEnsemblGenomes()` and `useEnsemblGenomes()` instead of `useEnsembl()`.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `AnnotationDbi (OrgDb)` | You need offline annotation; you need NCBI Entrez IDs as primary keys. | You need rich Ensembl attributes (GO, protein domains, ortholog) not in OrgDb. |
| `EnsDb (ensembldb)` | You want a local, reproducible Ensembl annotation database integrated with Bioconductor. | You need the most current Ensembl data without delay. |

## Benchmark Evidence

*Key studies that have validated or benchmarked this tool:*

- **Durinck S et al. (2009). Nat Protocols 4:1184.** [PMID:19247284](https://pubmed.ncbi.nlm.nih.gov/19247284)  
  biomaRt enables programmatic access to Ensembl, replacing manual download of annotation files.

## Common Errors & Troubleshooting

### `Timeout / curl error connecting to Ensembl`

**Cause:** Server overloaded or geographic mirror slow

**Fix:** Try `useEnsembl(mirror='useast')` or an archived version with `host=`

### `Error in getBM: dataset ... not found`

**Cause:** Dataset name misspelled

**Fix:** Run `listDatasets(ensembl)` to get exact dataset names

## Additional Notes from Official Documentation

*Extracted from the biomaRt Bioconductor vignette(s)*

### Contents


1 Introduction
2 Selecting an Ensembl BioMart database and dataset 2.1 Step1: Identifying the database you need 2.2 Step 2: Choosing a dataset 2.3 Ensembl mirror sites 2.4 Using archived versions of Ensembl 2.5 Using Ensembl Genomes
2.1 Step1: Identifying the database you need
2.2 Step 2: Choosing a dataset
2.3 Ensembl mirror sites
2.4 Using archived versions of Ensembl
2.5 Using Ensembl Genomes
3 How to build a biomaRt query 3.1 Searching for filters and attributes 3.2 Using predefined filter values 3.3 Finding out more information on filters 3.3.1 filterType 3.4 Attribute Pages 3.5 Using select()
3.1 Searching for filters and attributes
3.2 Using predefined filter values
3.3 Finding out more information on filters 3.3.1 filterType
3.3.1 filterType
3.4 Attribute Pages
3.5 Using select()


### 1 Introduction


Accessing the data available in Ensembl is by far most frequent use of the biomaRt package. With that in mind biomaRt provides a number of functions that are tailored to work specifically with the BioMart instances provided by Ensembl. This vignette details this Ensembl specific functionality and provides a number of example usecases that can be used as the basis for specifying your own queries.

### 2 Selecting an Ensembl BioMart database and dataset


Every analysis with biomaRt starts with selecting a BioMart database to use. The commands below will connect us to Ensemblâs most recent version of the Human Genes BioMart.
If this your first time using biomaRt , you might wonder how to find the two arguments we supplied to the useEnsembl() command. This is a two step process, but once you know the setting you need you can use the version shown above as a single command. These initial steps are outlined below.

```r
library(biomaRt)
ensembl <- useEnsembl(biomart = "genes", dataset = "hsapiens_gene_ensembl")
```

### 2.1 Step1: Identifying the database you need


The first step is to find the names of the BioMart services Ensembl is currently providing. We can do this using the function listEnsembl() , which will display all available Ensembl BioMart web services. The first column gives us the name we should provide to the biomart argument in useEnsembl() , and the second gives a more comprehensive title for the dataset along with the Ensembl version.
The useEnsembl() function can now be used to connect to the desired BioMart database. The biomart argument should be given a valid name from the output of listEnsembl() . In the next example we will select the main Ensembl mart, which provides access to gene annotation information.
If we print the current ensembl object, we can see that the ENSEMBL_MART_ENSEMBL database 1 1 1 this is how Ensembl name

```r
listEnsembl()
```

```r
##         biomart                version
## 1         genes      Ensembl Genes 115
## 2 mouse_strains      Mouse strains 115
## 3          snps  Ensembl Variation 115
## 4    regulation Ensembl Regulation 115
```

### 2.2 Step 2: Choosing a dataset


BioMart databases can contain several datasets. For example, within the Ensembl genes mart every species is a different dataset. In the next step we look at which datasets are available in the selected BioMart by using the function listDatasets() . Note: here we use the function head() to display only the first 5 entries as the complete list has many entries.
The listDatasets() function will return every available option, however this can be unwieldy when the list of results is long, involving much scrolling to find the entry you are interested in. biomaRt also provides the functions searchDatasets() which will try to find any entries matching a specific term or pattern. For example, if we want to find the details of any datasets in our ensembl mart that contain the term â hsapiens â 

```r
datasets <- listDatasets(ensembl)
head(datasets)
```

```r
##                        dataset                           description     version
## 1 abrachyrhynchus_gene_ensembl Pink-footed goose genes (ASM259213v1) ASM259213v1
## 2     acalliptera_gene_ensembl      Eastern happy genes (fAstCal1.3)  fAstCal1.3
## 3   acarolinensis_gene_ensembl       Green anole genes (AnoCar2.0v2) AnoCar2.0v2
## 4    acchrysaetos_gene_ensembl       Golden eagle genes (bAquChr1.2)  bAquChr1.2
## 5    acitrinellus_gene_ensembl        Midas cichlid genes (Midas_v5)    Midas_v5
## 6    amelanoleuca_gene_ensembl       Giant panda genes (ASM200744v2) ASM200744v2
```

### 2.3 Ensembl mirror sites


To improve performance Ensembl provides several mirrors of their site distributed around the globe. When you use the default settings for useEnsembl() your queries will be directed to your closest mirror geographically. In theory this should give you the best performance, however this is not always the case in practice. For example, if the nearest mirror is experiencing many queries from other users it may perform poorly for you. You can use the mirror argument to useEnsembl() to explicitly request a specific mirror.
Values for the mirror argument are: useast , asia , and www .

```r
ensembl <- useEnsembl(
  biomart = "ensembl",
  dataset = "hsapiens_gene_ensembl",
  mirror = "useast"
)
```

### 2.4 Using archived versions of Ensembl


It is possible to query archived versions of Ensembl through biomaRt , so you can maintain consistent annotation throughout the duration of a project.
biomaRt provides the function listEnsemblArchives() to view the available Ensembl archives. This function takes no arguments, and produces a table containing the name and version number of the available archives, the date they were first released, and the URL where they can be accessed.
Alternatively, one can use the https://www.ensembl.org website to find an archived version. From the main page scroll down the bottom of the page, click on âview in Archiveâ and select the archive you need.
You will notice that there is an archive URL even for the current release of Ensembl. It can be useful to use this if you wish to ensure that script 

```r
listEnsemblArchives()
```

```r
##              name     date                                 url version current_release
## 1  Ensembl GRCh37 Feb 2014          https://grch37.ensembl.org  GRCh37                
## 2     Ensembl 115 Sep 2025 https://sep2025.archive.ensembl.org     115               *
## 3     Ensembl 114 May 2025 https://may2025.archive.ensembl.org     114                
## 4     Ensembl 113 Oct 2024 https://oct2024.archive.ensembl.org     113                
## 5     Ensembl 112 May 2024 https://may2024.archive.ensembl.org     112                
## 6     Ensembl 111 Jan 2024 https://jan2024.archive.ensembl.org     111                
## 7     Ensembl 110 Jul 2023 https://jul2023.archive.ensembl.org     110                
## 8     Ensembl 109 Feb 2023 https://feb2023.archive.ensembl.org     109                
## 9     Ensembl 108 Oct 2022 https://oct2022.archive.ensembl.org     108                
## 10    Ensembl 107 Jul 2022 https://jul2022.archive.ensembl.org     107                
## 11    Ensembl 106 Apr 2022 https://apr2022.archive.ensembl.org     106                
## 12    Ensembl 105 Dec 2021 https://dec2021.archive.ensembl.org     105                
## 13    Ensembl 104 May 2021 https://may2021.archive.ensembl.org     104                
## 14    Ensembl 103 Feb 2021 https://feb2021.archive.ensembl.org     103                
## 15    Ensembl 102 Nov 2020 https://nov2020.archive.ensembl.org     102                
## 16    Ensembl 101 Aug 2020 https://aug2020.archive.ensembl.org     101                
## 17    Ensembl 100 Apr 2020 https://apr2020.archive.ensembl.org     100                
## 18     Ensembl 80 May 2015 https://may2015.archive.ensembl.org      80                
## 19     Ensembl 77 Oct 2014 https://oct2014.archive.ensembl.org      77                
## 20     Ensembl 75 Feb 2014 https://feb2014.archive.ensembl.org      75                
## 21     Ensembl 54 May 2009 https://may2009.archive.ensembl.org      54
```

### 2.5 Using Ensembl Genomes


Ensembl Genomes expands the effort to provide annotation from the vertebrate genomes provided by the main Ensembl project across taxonomic space, with separate BioMart interfaces for Protists, Plants, Metazoa and Fungi. 2 2 2 Note: Unfortunately there is no BioMart interface to the Ensembl Bacteria data. The number of bacterial genomes is in the tens of thousands and BioMart does not perform well when providing data on that scale .
You can use the functions listEnsemblGenomes() and useEnsemblGenomes() in similar fashion to the functions shown previously. For example first we can list the available Ensembl Genomes marts:
We can the select the Ensembl Plants database, and search for the dataset name for Arabidopsis.
We can then use this information to create our Mart object that will access

```r
listEnsemblGenomes()
```

```r
##               biomart                        version
## 1       protists_mart      Ensembl Protists Genes 62
## 2 protists_variations Ensembl Protists Variations 62
## 3          fungi_mart         Ensembl Fungi Genes 62
## 4    fungi_variations    Ensembl Fungi Variations 62
## 5        metazoa_mart       Ensembl Metazoa Genes 62
## 6  metazoa_variations  Ensembl Metazoa Variations 62
## 7         plants_mart        Ensembl Plants Genes 62
## 8   plants_variations   Ensembl Plants Variations 62
```

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/biomaRt.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/html/biomaRt.html
- **GitHub:** 
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Durinck S et al. (2009). Nature Protocols, 4:1184-1191.

---
