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

## Code Example

```r
#!/usr/bin/env Rscript
    
    # Load required libraries
    library(biomaRt)
    
    # ==========================================
    # STAGE 1: Defensive Input Reading & Parsing
    # ==========================================
    
    input_file <- "input.csv"
    ids <- character()
    
    if (file.exists(input_file)) {
      message("Reading input file: ", input_file)
      input_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
      
      if (ncol(input_data) > 0) {
        if ("feature_id" %in% colnames(input_data)) {
          ids <- as.character(input_data\$feature_id)
        } else if (ncol(input_data) == 1) {
          ids <- as.character(input_data[[1]])
        } else {
          ids <- as.character(rownames(input_data))
        }
      }
    } else {
      message("Input file not found. Proceeding with fallback IDs.")
    }
    
    # Clean and deduplicate IDs
    ids <- unique(ids[!is.na(ids) & ids != ""])
    
    # Fallback to standard Ensembl Gene IDs if input is empty or invalid
    if (length(ids) == 0) {
      message("No valid identifiers found. Using default Ensembl Gene IDs (TP53, BRCA2, GAPDH) for robustness.")
      ids <- c("ENSG00000141510", "ENSG00000139618", "ENSG00000111640")
      filter_type <- "ensembl_gene_id"
    } else {
      # Heuristic to determine the filter type based on ID patterns
      if (any(grepl("^ENSG", ids))) {
        filter_type <- "ensembl_gene_id"
      } else if (any(grepl("_at\$", ids))) {
        filter_type <- "affy_hg_u133_plus_2"
      } else if (any(grepl("^[0-9]+\$", ids))) {
        filter_type <- "entrezgene_id"
      } else {
        filter_type <- "hgnc_symbol"
      }
    }
    
    message("Determined filter type: ", filter_type)
    message("Processing ", length(ids), " unique identifiers.")
    
    # ==========================================
    # STAGE 2: Establish Connection to BioMart
    # ==========================================
    
    # Configure SSL settings defensively to avoid common handshake/certificate errors
    tryCatch({
      setEnsemblSSL(list(ssl_verifypeer = FALSE))
    }, error = function(e) {
      message("Warning: Could not set SSL settings: ", e\$message)
    })
    
    # Connect to Ensembl Human Genes dataset
    ensembl <- tryCatch({
      useEnsembl(biomart = "genes", dataset = "hsapiens_gene_ensembl")
    }, error = function(e) {
      message("Primary connection failed. Attempting US East mirror...")
      tryCatch({
        useEnsembl(biomart = "genes", dataset = "hsapiens_gene_ensembl", mirror = "useast")
      }, error = function(err2) {
        stop("Fatal: Unable to connect to Ensembl BioMart. Error: ", err2\$message)
      })
    })
    
    # Print cache information for diagnostic purposes
    tryCatch({
      print(biomartCacheInfo())
    }, error = function(e) {
      message("Could not retrieve cache info.")
    })
    
    # ==========================================
    # STAGE 3: Retrieve Basic Gene Annotations
    # ==========================================
    
    message("Retrieving basic gene annotations...")
    attributes_to_retrieve <- c(
      "ensembl_gene_id", 
      "hgnc_symbol", 
      "chromosome_name", 
      "start_position", 
      "end_position", 
      "band", 
      "description"
    )
    
    annot_df <- tryCatch({
      getBM(
        attributes = attributes_to_retrieve,
        filters = filter_type,
        values = ids,
        mart = ensembl
      )
    }, error = function(e) {
      message("Error retrieving basic annotations: ", e\$message)
      # Return empty dataframe with expected structure
      data.frame(matrix(ncol = length(attributes_to_retrieve), nrow = 0, 
                        dimnames = list(NULL, attributes_to_retrieve)))
    })
    
    write.csv(annot_df, "gene_annotations.csv", row.names = FALSE)
    
    # ==========================================
    # STAGE 4: Retrieve Gene Ontology (GO) Terms
    # ==========================================
    
    message("Retrieving Gene Ontology annotations...")
    go_attributes <- c("ensembl_gene_id", "go_id", "name_1006", "namespace_1003")
    
    # Use mapped Ensembl IDs if available for more reliable downstream queries
    query_ids <- ids
    query_filter <- filter_type
    if (filter_type != "ensembl_gene_id" && nrow(annot_df) > 0) {
      mapped_ids <- unique(annot_df\$ensembl_gene_id)
      mapped_ids <- mapped_ids[mapped_ids != "" & !is.na(mapped_ids)]
      if (length(mapped_ids) > 0) {
        query_ids <- mapped_ids
        query_filter <- "ensembl_gene_id"
      }
    }
    
    go_df <- tryCatch({
      getBM(
        attributes = go_attributes,
        filters = query_filter,
        values = query_ids,
        mart = ensembl
      )
    }, error = function(e) {
      message("Error retrieving GO annotations: ", e\$message)
      data.frame(matrix(ncol = length(go_attributes), nrow = 0, 
                        dimnames = list(NULL, go_attributes)))
    })
    
    write.csv(go_df, "go_annotations.csv", row.names = FALSE)
    
    # ==========================================
    # STAGE 5: Retrieve Promoter Sequences
    # ==========================================
    
    message("Retrieving 100bp upstream promoter sequences...")
    seq_df <- tryCatch({
      getSequence(
        id = query_ids,
        type = query_filter,
        seqType = "coding_gene_flank",
        upstream = 100,
        mart = ensembl
      )
    }, error = function(e) {
      message("Error retrieving sequences: ", e\$message)
      data.frame(coding_gene_flank = character(), ensembl_gene_id = character())
    })
    
    write.csv(seq_df, "promoter_sequences.csv", row.names = FALSE)
    
    # ==========================================
    # STAGE 6: Retrieve Mouse Homologs
    # ==========================================
    
    message("Mapping human genes to mouse homologs...")
    homologs_df <- tryCatch({
      ens_ids <- query_ids
      if (query_filter != "ensembl_gene_id" && nrow(annot_df) > 0) {
        ens_ids <- unique(annot_df\$ensembl_gene_id)
      }
      ens_ids <- ens_ids[grepl("^ENSG", ens_ids)]
      
      if (length(ens_ids) > 0) {
        getHomologs(
          ensembl_gene_ids = ens_ids,
          species_from = "human",
          species_to = "mouse"
        )
      } else {
        data.frame(ensembl_gene_id = character(), mmusculus_homolog_ensembl_gene = character())
      }
    }, error = function(e) {
      message("Error mapping homologs: ", e\$message)
      data.frame(ensembl_gene_id = character(), mmusculus_homolog_ensembl_gene = character())
    })
    
    # Retrieve detailed coordinates and RefSeq IDs for the mouse homologs
    mouse_details_df <- data.frame(
      ensembl_gene_id = character(), 
      refseq_mrna = character(), 
      chromosome_name = character(), 
      start_position = integer()
    )
    
    if (nrow(homologs_df) > 0) {
      mouse_ids <- unique(homologs_df\$mmusculus_homolog_ensembl_gene)
      mouse_ids <- mouse_ids[mouse_ids != "" & !is.na(mouse_ids)]
      
      if (length(mouse_ids) > 0) {
        message("Retrieving mouse homolog details...")
        mouse_details_df <- tryCatch({
          mouse_mart <- useEnsembl(biomart = "genes", dataset = "mmusculus_gene_ensembl")
          getBM(
            mart = mouse_mart,
            filters = "ensembl_gene_id",
            values = mouse_ids,
            attributes = c("ensembl_gene_id", "refseq_mrna", "chromosome_name", "start_position")
          )
        }, error = function(e) {
          message("Error retrieving mouse details: ", e\$message)
          data.frame(ensembl_gene_id = character(), refseq_mrna = character(), 
                     chromosome_name = character(), start_position = integer())
        })
      }
    }
    
    # Merge homology mapping with mouse details
    final_homology_df <- merge(
      homologs_df, 
      mouse_details_df, 
      by.x = "mmusculus_homolog_ensembl_gene", 
      by.y = "ensembl_gene_id", 
      all.x = TRUE
    )
    
    write.csv(final_homology_df, "mouse_homologs.csv", row.names = FALSE)
    
    # ==========================================
    # STAGE 7: Diagnostics & Visualization
    # ==========================================
    
    message("Generating diagnostic plots...")
    pdf("chromosome_distribution.pdf", width = 8, height = 6)
    
    if (nrow(annot_df) > 0 && "chromosome_name" %in% colnames(annot_df)) {
      chrom_counts <- table(annot_df\$chromosome_name)
      # Sort chromosomes numerically/alphabetically
      chrom_names <- names(chrom_counts)
      suppressWarnings({
        numeric_chroms <- as.numeric(chrom_names)
      })
      order_idx <- order(is.na(numeric_chroms), numeric_chroms, chrom_names)
      chrom_counts <- chrom_counts[order_idx]
      
      barplot(
        chrom_counts,
        las = 2,
        col = "skyblue",
        main = "Distribution of Annotated Genes Across Chromosomes",
        xlab = "Chromosome",
        ylab = "Number of Genes"
      )
    } else {
      # Fallback empty plot if no data is available
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, "No chromosome data available to plot.", cex = 1.2)
    }
    
    dev.off()
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_BIOMART_BIOMART_GENOMIC_ANNOTATION":
        biomaRt: \$(Rscript -e 'cat(as.character(packageVersion("biomaRt")))')
    END_VERSIONS
```
