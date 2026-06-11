# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CSAR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CSAR)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the example dataset provided by the CSAR package
data("CSAR-dataset")

# The vignette does not provide data-preparation code for TAIR8_genes_test.
# However, the workflow reads it from "genes.gff" using read.delim(..., header=TRUE).
# The distance2Genes function uses this object, and the output 'd' shows 'gene' and 'le' (length).
# This implies TAIR8_genes_test should be a data frame with gene annotation information,
# including chromosome, start, end, strand, and a gene identifier.
# We create a minimal, plausible