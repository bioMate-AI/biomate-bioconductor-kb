# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CBEA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CBEA)

# Generate synthetic abundance matrix (samples as rows, taxa as columns)
set.seed(123)
abundance_matrix <- matrix(runif(100), nrow = 10, ncol = 10)
rownames(abundance_matrix) <- paste0("Sample", 1:10)
colnames(abundance_matrix) <- paste0("Taxon", 1:10)

# Normalize to relative abundance (proportions)
abundance_matrix <- abundance_matrix / rowSums(abundance_matrix)

write.csv(abundance_matrix, "abundance_matrix.csv", row.names = TRUE)

# Generate synthetic GMT file for taxa sets
gmt_content <- c(
  "Set1\tDescription1\tTaxon1\tTaxon2\tTaxon3",
  "Set2\tDescription2\tTaxon4\tTaxon5\tTaxon6",
  "Set3\tDescription3\tTaxon7\tTaxon8\tTaxon9\tTaxon10"
)
writeLines(gmt_content, "taxa_sets.gmt")