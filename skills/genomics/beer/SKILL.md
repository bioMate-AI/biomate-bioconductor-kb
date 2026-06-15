---
name: bioconductor-beer
description: BEER implements a Bayesian model for analyzing phage-immunoprecipitation sequencing (PhIP-seq) data. Given a PhIPData object, BEER returns posterior probabilities of enriched antibody responses, point estimates for the relative fold-change in comparison to negative control samples, and more. Additionally, BEER provides a convenient implementation for using edgeR to identify enriched antibody responses.
when_to_use: Use when: BEER implements a Bayesian model for analyzing phage-immunoprecipitation sequencing (PhIP-seq) data. Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# beer

## Workflows

### Standard Workflow

Identify enriched antibody responses to peptides in PhIP-seq data using edgeR and Bayesian (BEER) modeling.

```r
library(beer)

# Load simulated PhIPData
data_path <- system.file("extdata/sim_data.rds", package = "beer")
sim_data <- readRDS(data_path)

# 1. Run edgeR to estimate peptide-specific dispersion
edgeR_out <- runEdgeR(sim_data, assay.names = c(logfc = "edgeR_logfc", prob = "edgeR_logpval"))

# 2. Run BEER (brew) to identify enriched peptides (hits)
assay_locations <- c(phi = "beer_fc_marg", phi_Z = "beer_fc_cond", Z = "beer_prob", c = "sampleInfo", pi = "sampleInfo")
beer_out <- brew(edgeR_out, assay.names = assay_locations)

# Identify hits by combining posterior probabilities and super-enriched peptides
was_run <- matrix(rep(beer_out$group != "beads", each = nrow(beer_out)), nrow = nrow(beer_out))
are_se <- was_run & is.na(assay(beer_out, "beer_prob"))
assay(beer_out, "beer_hits") <- assay(beer_out, "beer_prob") > 0.5 | are_se

# 3. Run beads-only round robin to estimate false positive rates
beer_beadsRR <- beadsRR(beer_out, method = "beer", assay.names = assay_locations)

# 4. Calculate expected reads/proportions and Bayes factors
expected_data <- getExpected(sim_data)
bf_data <- getBF(beer_out)
```

*Input: A PhIPData object containing PhIP-seq read counts; Output: A PhIPData object updated with enrichment hits, posterior probabilities, and Bayes factors.*

## When to Use
- Analyzing PhIP-seq (phage immunoprecipitation sequencing) data to identify enriched antibody responses to peptides.
- When you want to run standard differential expression analysis using `runEdgeR` on PhIP-seq data.
- When you want to apply a Bayesian hierarchical model via `brew` to estimate posterior probabilities of enrichment and relative fold-changes.
- When you want to estimate false positive rates using a beads-only round robin via `beadsRR`.

## When NOT to Use
- For general RNA-seq differential expression without a PhIP-seq design or negative control (beads-only) samples. Use standard `edgeR` or `DESeq2` directly.

## Data Requirements
- A `PhIPData` object (e.g., loaded from `sim_data.rds` in the vignette) containing read counts for samples and peptides, with designated beads-only control samples.

## Key Parameters
- **assay.names** (NULL): Named vector specifying where to store summarized MCMC output (e.g., `phi`, `phi_Z`, `Z`, `c`, `pi`).
- **beadsRR** (FALSE): Logical indicating whether to run beads-only round robin within `brew` or `runEdgeR`.
- **de.method** ("exactTest"): Method for edgeR differential expression, either "exactTest" or "glmQLFTest".
- **a_pi** (2): Prior shape parameter for the beta distribution describing the proportion of enriched peptides.
- **b_pi** (300): Prior shape parameter for the beta distribution describing the proportion of enriched peptides.
- **a_phi** (1.25): Prior shape parameter for the gamma distribution describing fold-change for enriched peptides.
- **b_phi** (0.1): Prior shape parameter for the gamma distribution describing fold-change for enriched peptides.
- **fc** (1): Minimum fold-change for an enriched peptide.

## Best Practices
- Run `runEdgeR` first to quickly identify enriched peptides and provide a baseline comparison.
- Identify and exclude "super-enriched" peptides (e.g., fold-change > 15) before running the MCMC to speed up BEER execution.
- Use parallelization via `BiocParallel::SerialParam()` or `BiocParallel::SnowParam()` passed to `BPPARAM` to speed up the Bayesian model.
- Verify MCMC convergence by saving samples to a directory and plotting trace/density plots using `coda` or `plot`.

## Common Pitfalls
- MCMC sampler getting stuck during execution. Fix: Ensure prior beta shape parameters (e.g., estimated via `getAB`) are greater than one.
- Extremely slow execution times for large datasets. Fix: Set a conservative threshold for removing super-enriched peptides to reduce the number of peptides modeled by MCMC.

## Alternatives
- `edgeR` directly for standard negative binomial differential expression.
- `DESeq2` for alternative parametric differential expression analysis.

## Citations
- Chen A, Kammers K, Larman HB, Scharpf R, Ruczinski I (2022). Detecting antibody reactivities in phage immunoprecipitation sequencing data. bioRxiv.
- Robinson MD, McCarthy DJ and Smyth GK (2010). edgeR: a Bioconductor package for differential expression analysis of digital gene expression data. Bioinformatics.

## References
- Homepage: bioconductor.org/packages/beer
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/beer/inst/doc/beer.html
