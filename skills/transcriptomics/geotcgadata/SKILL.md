---
name: bioconductor-geotcgadata
description: Gene Expression Omnibus(GEO) and The Cancer Genome Atlas (TCGA) provide us with a wealth of data, such as RNA-seq, DNA Methylation, SNP and Copy number variation data. It's easy to download data from TCGA using the gdc tool, but processing these data into a format suitable for bioinformatics analysis requires more work. This R package was developed to handle these data.
when_to_use: Use when: GeoTcgaData; Differential expression analysis (GeoTcgaData); ATAC-seq chromatin accessibility (GeoTcgaData). Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# GeoTcgaData

## Workflows

### Tcga Id Conversion And Normalization

Convert TCGA ENSEMBL gene IDs to gene symbols and normalize raw counts to FPKM or TPM.

```r
library(GeoTcgaData)

# 1. Read user inputs
data(profile)
data(gene_cov)

# 2. Convert TCGA ENSEMBL gene IDs to gene symbols
result_sym <- id_conversion_TCGA(profile)

# 3. Convert raw counts to FPKM
lung_squ_count2 <- matrix(c(1,2,3,4,5,6,7,8,9), ncol=3)
rownames(lung_squ_count2) <- c("DISC1","TCOF1","SPPL3")
colnames(lung_squ_count2) <- c("sample1","sample2","sample3")
result_fpkm <- countToFpkm(lung_squ_count2, keyType = "SYMBOL", gene_cov = gene_cov)

# 4. Convert raw counts to TPM
result_tpm <- countToTpm(lung_squ_count2, keyType = "SYMBOL", gene_cov = gene_cov)
```
*Input: A raw count matrix and a gene coverage data frame (`gene_cov`); Output: Converted gene symbols, FPKM, or TPM matrices.*

### Standard Workflow

Perform differential expression analysis on RNA-seq count data using a Wilcoxon test or other methods.

```r
library(GeoTcgaData)

# 1. Prepare the count matrix and group vector
df <- matrix(rnbinom(400, mu = 4, size = 10), 25, 16)
df <- as.data.frame(df)
rownames(df) <- paste0("gene", 1:25)
colnames(df) <- paste0("sample", 1:16)
group <- sample(c("group1", "group2"), 16, replace = TRUE)

# 2. Run differential_RNA to identify differentially expressed genes (Method 1: using data frame)
result1 <- differential_RNA(counts = df, group = group, filte = FALSE, method = "Wilcoxon")

# 3. Run differential_RNA to identify differentially expressed genes (Method 2: using SummarizedExperiment)
colData <- S4Vectors::DataFrame(row.names = colnames(df), group = group)
data <- SummarizedExperiment::SummarizedExperiment(assays=S4Vectors::SimpleList(counts=as.matrix(df)), colData = colData)
result2 <- differential_RNA(counts = data, groupCol = "group", filte = FALSE, method = "Wilcoxon")
```
*Input: A count matrix (or `SummarizedExperiment`) and sample group annotations; Output: A data frame of differential expression results.*

### Cnv Differential Analysis

Identify genes with differential copy number variations between groups.

```r
library(GeoTcgaData)

# 1. Prepare the copy number score matrix and sample groups
aa <- matrix(sample(c(0, 1, -1), 200, replace = TRUE), 25, 8)
rownames(aa) <- paste0("gene", 1:25)
colnames(aa) <- paste0("sample", 1:8)
sampleGroup <- sample(c("A", "B"), ncol(aa), replace = TRUE)

# 2. Run differential_CNV to extract differential CNV genes
diffCnv <- differential_CNV(aa, sampleGroup)
```
*Input: A gene-level copy number score matrix and a group vector; Output: A data frame of genes with differential copy number variations.*

### Dna Methylation Differential Analysis

Identify differentially methylated genes from CpG methylation data.

```r
library(GeoTcgaData)

# 1. Prepare CpG methylation matrix, sample groups, and CpG-to-gene mapping
cpgData <- matrix(runif(2000), nrow = 200, ncol = 10)
rownames(cpgData) <- paste0("cpg", seq_len(200))
colnames(cpgData) <- paste0("sample", seq_len(10))
sampleGroup <- c(rep("group1", 5), rep("group2", 5))
names(sampleGroup) <- colnames(cpgData)
cpg2gene <- data.frame(cpg = rownames(cpgData), gene = rep(paste0("gene", seq_len(20)), 10))

# 2. Run differential_methy to identify differentially methylated genes
result <- differential_methy(cpgData, sampleGroup, cpg2gene = cpg2gene, normMethod = NULL)
```
*Input: A CpG methylation beta-value matrix, sample group vector, and a CpG-to-gene mapping data frame; Output: A data frame of differentially methylated genes.*

### Geo Chip Data Preprocessing

Preprocess GEO microarray data by averaging duplicate gene symbols and resolving multi-mapped probe IDs.

```r
library(GeoTcgaData)

# 1. Average expression values of different IDs for the same gene using gene_ave
file_gene_ave <- data.frame(Gene = c("MARCH1","MARC1","MARCH1"), GSM1 = c(2.9, 4.7, 8.1), GSM2 = c(3.9, 5.7, 7.1))
result_ave <- gene_ave(file_gene_ave, 1)

# 2. Resolve multi-mapped probe IDs by either assigning the expression to each gene using repAssign or deleting them using repRemove
input_file <- data.frame(aa = c("MARCH1 /// MMA", "MARC1"), bb = c("2.9", "4.7"), cc = c("3.9", "5.7"))
repAssign_result <- repAssign(input_file, " /// ")
repRemove_result <- repRemove(input_file, " /// ")
```
*Input: A data frame of probe/gene expression values with potential duplicate or multi-mapped IDs; Output: A cleaned data frame with unique gene symbols.*

## When to Use
- To perform differential expression analysis on RNA-seq count data using Wilcoxon rank-sum tests via `differential_RNA()`.
- To convert TCGA ENSEMBL gene IDs to gene symbols using `id_conversion_TCGA()`.
- To normalize raw RNA-seq counts to FPKM or TPM using `countToFpkm()` and `countToTpm()`.
- To identify differentially methylated genes from CpG methylation matrices using `differential_methy()`.
- To preprocess GEO microarray data by averaging duplicate gene symbols with `gene_ave()` and resolving multi-mapped probe IDs with `repAssign()` or `repRemove()`.

## When NOT to Use
- For complex multi-factor experimental designs in RNA-seq differential expression, use `DESeq2` or `edgeR` because `differential_RNA()` is designed for simple two-group comparisons.
- For advanced microarray normalization and linear modeling, use `limma` because `GeoTcgaData` focuses on basic ID averaging and multi-mapping resolution.

## Data Requirements
- **Input Format**: Standard R `matrix` or `data.frame`, or a `SummarizedExperiment` object.
- **Structure**: Gene expression matrices should have genes/probes as rows and samples as columns.
- **Normalization State**: Raw counts are required for `countToFpkm()` and `countToTpm()`. Methylation data should be beta-values or similar continuous matrices.

## Key Parameters
- **counts** (NULL): Input count matrix or `SummarizedExperiment` object in `differential_RNA()`.
- **group** (NULL): Vector of sample group annotations in `differential_RNA()`.
- **filte** (TRUE): Logical indicating whether to filter low-expression genes in `differential_RNA()`.
- **method** ("Wilcoxon"): Statistical method for differential analysis in `differential_RNA()`.
- **keyType** ("SYMBOL"): Type of gene identifier used in `countToFpkm()` or `countToTpm()`.
- **gene_cov** (NULL): Gene coverage data frame used for length normalization in FPKM/TPM conversion.
- **normMethod** (NULL): Normalization method for methylation data in `differential_methy()`.
- **cpg2gene** (NULL): Data frame mapping CpG probe IDs to gene symbols in `differential_methy()`.

## Best Practices
- Perform quality control on SNP data using `SNP_QC()` before running differential SNP analysis with `differential_SNP()`.
- Use `model = "gene"` in methylation analysis to avoid bias related to the number of CpGs per gene.
- Ensure the gene coverage dataset `gene_cov` is loaded before running `countToFpkm()` or `countToTpm()`.

## Common Pitfalls
- **Using raw counts directly in downstream analyses without normalization**: Fix by converting counts to FPKM or TPM using `countToFpkm()` or `countToTpm()`.
- **Multi-mapped probe IDs causing duplicate rows**: Fix by using `repAssign()` or `repRemove()` to handle probe IDs mapped to multiple genes.
- **CpG number bias in methylation differential analysis**: Fix by setting the model to `"gene"` instead of `"cpg"` in `differential_methy()`.

## Alternatives
- `DESeq2` for robust parametric differential expression analysis of RNA-seq data.
- `edgeR` for differential expression analysis using empirical Bayes estimation.
- `limma` for linear modeling of microarray and RNA-seq data.
- `ChAMP` for comprehensive Illumina methylation integration and analysis.

## Citations
- Young et al. 2010, Genome Biol (for gene ontology selection bias).
- Oshlack and Wakefield 2009, Biol Direct (for transcript length bias).

## References
- Homepage: bioconductor.org/packages/GeoTcgaData
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/GeoTcgaData/inst/doc/GeoTcgaData.html
