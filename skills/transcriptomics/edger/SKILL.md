---
name: bioconductor-edger
description: Estimates differential gene expression for short read sequence count using methods appropriate for count data. If you have paired data you may also want to consider Tophat/Cufflinks. Input must be raw count data for each sequence arranged i
when_to_use: Use when: Appropriate for differential expression/abundance analysis of read count data from sequencing technologies (RNA-seq, ChIP-seq, ATAC-seq, BS-seq, CRISPR-Cas9 screens) with biological replication (or without replicates using specific workarounds).
user-invocable: false
---

# edgeR

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 4.10.1 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** limma
- **Imports:** locfit
- **Install:** `BiocManager::install("edgeR")`

## When to Use

- Bulk RNA-seq differential expression
- ChIP-seq read count differential binding
- ATAC-seq differential accessibility
- Multi-group comparisons with contrasts
- Complex experimental designs (factorial, nested, batch)

**Alternatives:** `DESeq2`, `limma-voom`, `NOISeq`

## Data Requirements

| Requirement | Details |
|-------------|----------|
| **Min Replicates** | ≥2 per group; n=2 is supported but power is very low |
| **Input Format** | Raw integer count matrix (genes × samples) |
| **Must Not Use** | Normalized values; edgeR normalizes internally via TMM |
| **Coverage** | ≥5M aligned reads per sample typical for bulk RNA-seq |

## Key Parameters

- **`coef`**: specifies the column(s) of the design matrix to drop for hypothesis testing
- **`contrast`**: numeric vector specifying a contrast of the linear model coefficients to test
- **`lfc`**: log2-fold-change threshold for testing differential expression above a specific fold-change
- **`keep.lib.sizes`**: controls whether library sizes are recalculated after filtering

## Workflow Variants

### Quasi Likelihood Pipeline

**Intent**: Perform differential expression analysis using the robust quasi-likelihood F-test framework.

**Inputs**:
- `TableOfCounts.txt (tab-delimited text file with gene counts and symbols)`

**Steps**:
1. Read count data and define groups
2. Create DGEList object
3. Filter lowly expressed genes
4. Normalize library sizes
5. Define design matrix
6. Fit QL GLM model
7. Perform quasi-likelihood F-test
8. Extract top differentially expressed genes.

```r
x <- read.delim("TableOfCounts.txt",row.names="Symbol")
group <- factor(c(1,1,2,2))
y <- DGEList(counts=x,group=group)
keep <- filterByExpr(y)
y <- y[keep,,keep.lib.sizes=FALSE]
y <- normLibSizes(y)
design <- model.matrix(~group)
fit <- glmQLFit(y,design)
qlf <- glmQLFTest(fit,coef=2)
topTags(qlf)
```


---

### Classic Pipeline

**Intent**: Perform pairwise differential expression analysis using exact tests (qCML method) for single-factor designs.

**Inputs**:
- `x (matrix of raw counts)`

**Steps**:
1. Create DGEList object with grouping
2. Estimate common and tagwise dispersions
3. Perform exact test
4. Extract top tags.

```r
y <- DGEList(counts=x, group=group)
y <- estimateDisp(y)
et <- exactTest(y)
topTags(et)
```


---

### Glm Lrt Pipeline

**Intent**: Perform differential expression analysis for complex multifactor designs using negative binomial GLMs and likelihood ratio tests.

**Inputs**:
- `y (DGEList object)`

**Steps**:
1. Define design matrix
2. Estimate dispersions with design matrix
3. Fit negative binomial GLM
4. Perform likelihood ratio test for specific coefficients or contrasts
5. Extract top tags.

```r
group <- factor(c(1,1,2,2,3,3))
design <- model.matrix(~group)
y <- estimateDisp(y, design)
fit <- glmFit(y, design)
lrt.2vs1 <- glmLRT(fit, coef=2)
topTags(lrt.2vs1)
```


---

### Fold Change Threshold Testing

**Intent**: Test for differential expression relative to a specific fold-change threshold using a rigorous statistical test.

**Inputs**:
- `y (DGEList object)`

**Steps**:
1. Define design matrix
2. Fit QL GLM model
3. Perform thresholded hypothesis testing
4. Extract top tags.

```r
fit <- glmQLFit(y, design)
tr <- glmTreat(fit, coef=2, lfc=1)
topTags(tr)
```


## Best Practices

- Use `filterByExpr()` for automatic gene filtering — it accounts for library size.
- TMM normalisation (`calcNormFactors`) is the default and works well for most datasets.
- Use `glmQLFit` + `glmQLFTest` for small sample sizes (n<10 per group).
- Use `glmFit` + `glmLRT` for large datasets — slightly more powerful but less robust.
- Always provide a design matrix (`model.matrix()`) for multi-factor experiments.
- For pairwise contrasts use `makeContrasts()` — do not subset samples post-hoc.
- Plot `plotBCV(d)` and `plotQLDisp(fit)` to check dispersion estimates.
- For ChIP-seq: use csaw windows instead of gene-level counts.

## Common Pitfalls

- Do not input predicted transcript abundances or transformed values (like RPKM/FPKM) instead of actual raw read counts
- Do not add artificial values to counts before inputting to edgeR
- Filtering should be based on factors involved in the DE analysis, not on blocking variables
- Avoid ad hoc fold-change cut-offs combined with p-value thresholds; use glmTreat instead.

## Alternatives

- **Rsubread/featureCounts/STAR/htseq-counts**: for aligning and producing count tables before edgeR
- **tximport/catchRSEM/catchKallisto/catchSalmon**: for transcript-level pseudoalignment/selective alignment data
- **EDASeq/cqn**: for sample-specific GC-content and gene length normalization (compatible via offset matrices)
- **limma**: mentioned in the context of empirical Bayes moderation strategies

## References

- Homepage: bioconductor.org/packages/edgeR
- Vignette: bioconductor.org/packages/release/bioc/vignettes/edgeR
