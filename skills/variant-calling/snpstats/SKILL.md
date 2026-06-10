---
name: bioconductor-snpstats
description: Classes and statistical methods for large SNP association studies. This extends the earlier snpMatrix package, allowing for uncertainty in genotypes.
when_to_use: Use when: Performing genome-wide association studies (GWAS) on large cohorts with hundreds of thousands of SNPs.; Analyzing imputed genotype data where genotypes are represented as posterior probabilities (uncertainty) rather than hard calls.; Calculating linkage disequilibrium (LD) statistics ($r^2$ and $D'$) and performing haplotype-based association testing.; Conducting family-based association tests, su. Not for: For modern, multi-million variant biobank-scale GWAS with complex population structure, use REGENIE or PLINK2 because snpStats is single-threaded and runs entirely in R memory.; For sequencing-based rare variant association tests (e.g., burden tests,
user-invocable: false
---

# snpStats

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.62.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Depends:** survival, Matrix
- **Imports:** BiocGenerics
- **System requirements:** URL
- **Install:** `BiocManager::install("snpStats")`

## When to Use
- Performing genome-wide association studies (GWAS) on large cohorts with hundreds of thousands of SNPs.
- Analyzing imputed genotype data where genotypes are represented as posterior probabilities (uncertainty) rather than hard calls.
- Calculating linkage disequilibrium (LD) statistics ($r^2$ and $D'$) and performing haplotype-based association testing.
- Conducting family-based association tests, such as the Transmission Disequilibrium Test (TDT).
- Calculating fixation index ($F_{ST}$) to measure genetic differentiation between populations.

## When NOT to Use
- For modern, multi-million variant biobank-scale GWAS with complex population structure, use `REGENIE` or `PLINK2` because snpStats is single-threaded and runs entirely in R memory.
- For sequencing-based rare variant association tests (e.g., burden tests, SKAT), use `SeqVarTools` or `GENESIS` because snpStats is optimized for common micro-array SNP data.

## Data Requirements
- **Input Format**: PLINK bed/bim/fam files, or imputed genotype files (e.g., IMPUTE2 format).
- **Structure**: Genotypes must be stored in the highly memory-efficient `SnpMatrix` or `XSnpMatrix` (for the X chromosome) classes, which pack genotypes into 1 byte per SNP.
- **Size**: Typically thousands of samples and up to 1 million SNPs.

## Key Parameters
- **snps**: A `SnpMatrix` or `XSnpMatrix` object containing the genotype data.
- **phenotype**: A vector or factor containing the target trait/phenotype for association testing.
- **covariates**: A data frame of confounding variables (e.g., age, sex, principal components) to include in the regression model.
- **depth** (1): The maximum distance (in number of SNPs) over which to calculate pairwise LD.
- **stats**: A logical indicating whether to return detailed test statistics or just p-values.

## Best Practices
- Perform rigorous quality control (QC) on the `SnpMatrix` using `col.summary()` and `row.summary()` to filter out samples/SNPs with high missingness, low minor allele frequency (MAF), or Hardy-Weinberg equilibrium (HWE) deviations.
- Always use the `XSnpMatrix` class for X-chromosome variants to correctly handle male hemizygosity and female heterozygosity.
- Use principal component analysis (PCA) on a pruned subset of independent SNPs to identify and control for population stratification.
- When working with imputed data, retain the probabilistic representation (uncertainty) to preserve statistical power and avoid bias from hard-calling.

## Common Pitfalls
- **Mismatched PLINK files**: Attempting to load PLINK files with mismatched sample or SNP counts causes import crashes. *Fix*: Verify that the `.bed`, `.bim`, and `.fam` files are perfectly synchronized and have not been modified independently.
- **Uncorrected population structure**: Running association tests without correcting for population structure leads to highly inflated QQ-plots. *Fix*: Extract the top principal components using `xxt()` and include them as covariates in `single.snp.tests()`.
- **Memory exhaustion during LD calculation**: Calculating pairwise LD across an entire chromosome can exhaust system memory. *Fix*: Restrict the LD calculation using the `depth` parameter or a sliding window of physical distance.

## Alternatives
- `GENESIS`: For association testing in samples with complex pedigree structures or ancestry, supporting both GDS and SnpMatrix formats.
- `gwascat`: For comparing GWAS results with the NHGRI-EBI GWAS Catalog.
- `GWASTools`: For comprehensive quality control and data management of genome-wide association studies.

## Citations
- Clayton, D. (2021). snpStats: SnpMatrix and XSnpMatrix classes and methods. *R package version 1.56.0*.
- Clayton, D., & Leung, H. T. (2007). An R package for association studies on locus-specific and genome-wide scales. *Human Heredity*, 64(1), 45-51.

## References
- Homepage: https://bioconductor.org/packages/snpStats
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/snpStats/inst/doc/snpStats-vignette.pdf
