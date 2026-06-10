# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("eisaR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(eisaR)

# The vignette excerpt indicates that count tables for exons and introns are used 
# for Exon-Intron Split Analysis (EISA). Since the exact count generation code 
# is truncated or relies on external alignments, we construct synthetic count 
# matrices matching the expected format for eisaR downstream functions.

set.seed(123)
n_genes <- 500
n_samples <- 6

gene_ids <- paste0("ENSG", sprintf("%011d", 1:n_genes))
sample_ids <- c("CondA_rep1", "CondA_rep2", "CondA_rep3", "CondB_rep1", "CondB_rep2", "CondB_rep3")

# Generate synthetic exonic count matrix
rawcounts_exonic <- matrix(
  rpois(n_genes * n_samples, lambda = 200),
  nrow = n_genes,
  ncol = n_samples,
  dimnames = list(gene_ids, sample_ids)
)

# Generate synthetic intronic count matrix (typically lower counts than exonic)
rawcounts_intronic <- matrix(
  rpois(n_genes * n_samples, lambda = 50),
  nrow = n_genes,
  ncol = n_samples,
  dimnames = list(gene_ids, sample_ids)
)

# Save to the expected RDS files
saveRDS(rawcounts_exonic, "rawcounts_exonic.rds")
saveRDS(rawcounts_intronic, "rawcounts_intronic.rds")