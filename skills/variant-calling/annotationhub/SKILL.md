---
name: bioconductor-annotationhub
description: This package provides a client for the Bioconductor AnnotationHub web resource. The AnnotationHub web resource provides a central location where genomic files (e.g., VCF, bed, wig) and other resources from standard locations (e.g., UCSC, En
when_to_use: Use when: Download organism annotation databases (OrgDb, TxDb, EnsDb); Get GTF/GFF files, chain files, FASTA sequences for any organism; Access reference genome resources without manual downloads
user-invocable: false
---

# AnnotationHub — Comprehensive Skill Guide

> **Domain:** Annotation / Genomics
> **Bioconductor:** [AnnotationHub](https://bioconductor.org/packages/release/bioc/html/AnnotationHub.html)
> **Paper:** Morgan M et al. (2021). Bioconductor package.

Access a large collection of biologically relevant annotation resources (genome sequences, chain files, GTF, OrgDbs, TxDbs) directly from within R via the Bioconductor AnnotationHub.

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 4.2.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** BiocGenerics, BiocFileCache
- **Imports:** RSQLite, BiocManager, BiocVersion, curl, rappdirs, AnnotationDbi, S4Vectors, httr2, yaml, dplyr, BiocBaseUtils
- **Install:** `BiocManager::install("AnnotationHub")`

## When to Use

- Download organism annotation databases (OrgDb, TxDb, EnsDb)
- Get GTF/GFF files, chain files, FASTA sequences for any organism
- Access reference genome resources without manual downloads

**Alternatives:** `GenomicFeatures::makeTxDbFromGFF()`, `biomaRt`, `BSgenome`

## Do NOT Use When

- Custom/proprietary genome builds not in Ensembl or UCSC.
- Real-time annotation updates — hub resources are versioned snapshots.

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Internet** | Required — downloads resources from Bioconductor servers (cached locally after first use) |
| **Cache** | ~500MB–5GB local cache typical for a project's annotation needs |

## Installation

```r
if (!require("BiocManager", quietly=TRUE))
    install.packages("BiocManager")
BiocManager::install("AnnotationHub")
library(AnnotationHub)
```

## Workflows

### Query and retrieve Bioconductor annotation resources
*Find and load genome annotations, ortholog mappings, and database snapshots*

#### Connect and search AnnotationHub

```r
library(AnnotationHub)
ah <- AnnotationHub()       # connects to Bioconductor AnnotationHub cloud

# Search by species and data type
query(ah, c("Homo sapiens", "EnsDb"))
query(ah, c("Mus musculus", "TxDb"))
query(ah, c("GRCh38", "gtf"))
```

#### Retrieve a specific resource

```r
# Fetch Ensembl 108 database for human
edb <- ah[["AH98047"]]       # EnsDb.Hsapiens.v108 equivalent
genes(edb)                   # returns GRanges of all genes

# Fetch GENCODE GTF as GRanges
gr <- ah[["AH49556"]]
```

#### Use OrgDb for gene-symbol mapping

```r
# Load human OrgDb
org_hs <- ah[["AH114084"]]   # org.Hs.eg.db snapshot
library(AnnotationDbi)
mapIds(org_hs, keys=c("BRCA1","TP53"), column="ENTREZID", keytype="SYMBOL")
```


## Key Functions & Parameters

### `AnnotationHub()()`

Create an AnnotationHub connection

| Parameter | Description |
|-----------|-------------|
| `cache` | local cache directory (default ~/.cache/AnnotationHub) |
| `ask` | ask before downloading (default TRUE) |

### `query()()`

Search the hub for resources

| Parameter | Description |
|-----------|-------------|
| `x` | AnnotationHub object |
| `pattern` | search terms (character vector, AND logic) |

### `ah[[id]]()`

Download and load a resource by its AH identifier (e.g. 'AH12345')


### `mcols()()`

View metadata for all resources in a filtered hub


### `display()()`

Interactive Shiny browser for AnnotationHub records


## Scientific Assumptions

*The method assumes the following about your data and experiment:*

- Hub resources are pre-curated and versioned — use the same resource ID for reproducibility.

## Result Interpretation

- Each resource has a unique AH identifier (e.g. AH98047) — record this for reproducibility.
- EnsDb objects: use `genes()`, `exons()`, `transcripts()` to extract annotation tables.
- TxDb objects: use `makeTxDbFromEnsembl()` alternatively for more control.

## Best Practices

- Use `query(ah, c('Homo sapiens', 'EnsDb', '109'))` to find species + resource type + version.
- Save downloads locally with `saveRDS()` to avoid re-downloading in each session.
- Set `options(timeout=300)` before downloading large resources.
- Use `ah$species` and `ah$rdataclass` columns to filter results before downloading.

## When to Choose This vs Alternatives

| Alternative | Prefer **this tool** when | Prefer **alternative** when |
|-------------|--------------------------|-----------------------------|
| `biomaRt` | You need live Ensembl queries with specific attribute/filter combinations. | You need offline/cached annotation; you want genome sequences or chain files. |

## Benchmark Evidence

*AnnotationHub is infrastructure rather than a statistical method; formal benchmarks
compare it against manual download pipelines.*

- **Morgan M, Shepherd L (2022). Bioconductor Annotation Infrastructure.** [Bioconductor Workflows](https://bioconductor.org/help/course-materials/)
  AnnotationHub reduces annotation retrieval from hours to seconds; reproducible snapshots
  improve cross-study comparability vs. manual genome downloads.

- **Gentleman RC et al. (2004). Genome Biol 5:R80.** [PMID:15461798](https://pubmed.ncbi.nlm.nih.gov/15461798)
  Foundational Bioconductor paper establishing annotation infrastructure that AnnotationHub
  extends; cited for the broader ecosystem providing interoperability guarantees.


## Common Errors & Troubleshooting

### `Error in .AnnotationHub_cache: cache invalid or corrupt`

**Cause:** Partial download or corrupted cache

**Fix:** Remove cache: `removeCache(ah); ah <- AnnotationHub()`

## Additional Notes from Official Documentation

*Extracted from the AnnotationHub Bioconductor vignette(s)*

### Contents


2 Troubleshooting 2.1 Accessing Behind A Proxy
2.1 Accessing Behind A Proxy
3 Other configuration options for resource downloading 3.1 Invalid Cache 3.2 Corrupt Cache 3.2.1 sqlite file 3.2.2 index file 3.2.3 resource path 3.2.4 resource id 3.3 Corrupt Database 3.4 Cannot retrieve resource 3.5 Offline localHub usage
3.1 Invalid Cache
3.2 Corrupt Cache 3.2.1 sqlite file 3.2.2 index file 3.2.3 resource path 3.2.4 resource id
3.2.1 sqlite file
3.2.2 index file
3.2.3 resource path
3.2.4 resource id
3.3 Corrupt Database
3.4 Cannot retrieve resource
3.5 Offline localHub usage
4 Group Hub/Cache Access
5 Lock file Troubleshooting 5.1 Permissions 5.2 Cannot lock file / no lock available
5.1 Permissions
5.2 Cannot lock file / no lock available
6 Default Caching Location Update 6.1 Option 1: Move cac

### 1 Overview


In spring 2019 the Hubs ( AnnotationHub / ExperimentHub ) upgraded their
backend to utilize BiocFileCache . This upgrade changed how resources were
downloaded and saved. While the Hub code itself ensures validity, it is possible
to access the BiocFileCache of resources directly without the Hub front ends,
which opens up the possibility of having caching problems. This document will
touch on some troubleshooting for these issues as well as any other frequently
asked issues. If the question or answer cannot be found here please ask on the Bioconductor Support Site or on the mailing list <bioc-devel@r-project.org>

### 2.1 Accessing Behind A Proxy


The ExperimentHub and AnnotationHub use CRAN package httr2 functions for accessing and downloading
web resources. This can be problematic if operating behind a
proxy. You can pass proxy information for Hubs by setting the options like the following:
Unfortunately unlike the previously used httr::set_config , there is no
option to globally set the proxy for httr2 requests. To get around this you can
also set a system wide environment variable âANNOTATION_HUB_PROXYâ for
AnnotationHub, âEXPERIMENT_HUB_PROXYâ for ExperimentHub, or âHUB_PROXYâ that
will work across all Hub classes (e.g.Â AnnotationHub and ExperimentHub)}

```r
proxy <- "http://my_user:my_password@myproxy:8080"
AnnotationHub::setAnnotationHubOption("PROXY", proxy)
## or 
ExperimentHub::setExperimentHubOption("PROXY", proxy)
```

### 3 Other configuration options for resource downloading


As mentioned previously, There is no global option like httr::set_config to
set configuration options when using httr2. A config argument may be passed to [[ and cache functions. This argument is a R list object that will be passed
to httr2::req_options . The names of the items should be valid curl options as
defined in curl::curl_options .

```r
ssl_opts <- list(verbose = 1L,ssl_verifypeer = 0L, ssl_verifyhost = 0L)
```

### 3.1 Invalid Cache


An invalid cache ERROR results from a missing sqlite or index file in the Hubâs
BiocFileCache. The Hub code needs these files in order to operate
correctly. Rerun the Hub constructor ( AnnotationHub() or ExperimentHub() )
again. If you were trying to run the constructor with localHub=TRUE , you
will have to run localHub=FALSE at least once to redownload the Hub sqlite
file.

### 3.2 Corrupt Cache


A corrupt cache ERROR results from multiple entries in the BiocFileCache
matching a query for a particular file. This will involve removing one,
multiple, or all entries for a file. Please see specific section below although
all follow the same principles.

### 3.2.1 sqlite file


If the sqlite file is the problematic file you should see something like the
following (maybe be experimenthub.sqlite3 respectively)
You will need to investigate the underlying BiocFileCache for the Hub and remove
some or all of the files so that there is only a single entry for the
filename. Call the BiocFileCache constructor with the path listed as cache in
the ERROR message.
Now we can query the BiocFileCache using the filename of the ERROR message.
This shows the number of entries for the filename. There should only be one row
You will need to deterime if you can validate which entry should remain by
evaluating the entries in the cache; [dplyr package][] methods may be useful for
parsing the tibble res object.
If you can identify which entry should be kept - remove the other entries i

```r
> ah = AnnotationHub()
Error: Corrupt Cache: sqlite file
  See AnnotationHub's TroubleshootingTheHubs vignette section on corrupt cache
  cache: /home/lori/.cache/AnnotationHub
  filename: annotationhub.sqlite3
```

```r
library(BiocFileCache)
bfc <- BiocFileCache("/home/lori/.cache/AnnotationHub")
```

### 3.2.1.1 redownload of sqlite file


A force redownload of the sqlite hub file can be achieved through the refreshHub
function. To specify which of the Bioconductor Hubs to redownload use the
hubClass argument with either AnnotationHub or ExperimentHub.

```r
ah2 = refreshHub(hubClass="AnnotationHub")
```

## Resources

- **Bioconductor page:** https://bioconductor.org/packages/release/bioc/html/AnnotationHub.html
- **Vignette:** https://bioconductor.org/packages/release/bioc/html/AnnotationHub.html
- **GitHub:** 
- **Bioconductor support forum:** https://support.bioconductor.org/
- **Paper:** Morgan M et al. (2021). Bioconductor package.

---
