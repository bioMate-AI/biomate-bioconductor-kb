# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("pairkat", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(pairkat)
library(SummarizedExperiment)

# Load the example dataset from the pairkat package
data("smokers", package = "pairkat")

# Extract the metabolomics assay and phenotype data
metabolome <- assays(smokers)$metabolomics
phenotype <- colData(smokers)

# Write the extracted data to the required input files
write.csv(as.data.frame(metabolome), file = "intensity.csv", row.names = TRUE)
write.csv(as.data.frame(phenotype), file = "coldata.csv", row.names = TRUE)