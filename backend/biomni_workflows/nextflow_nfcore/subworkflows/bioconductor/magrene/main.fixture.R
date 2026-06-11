# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("magrene")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(magrene)

# Load the example datasets provided by the package
data("gma_grn", package = "magrene")
data("gma_ppi", package = "magrene")
data("gma_paralogs", package = "magrene")

# Serialize the objects to the required input files
write.table(gma_grn, file = "grn_edgelist.tsv", sep = "\t", quote = FALSE, row.names = FALSE)
write.table(gma_ppi, file = "ppi_edgelist.tsv", sep = "\t", quote = FALSE, row.names = FALSE)
write.table(gma_paralogs, file = "paralog_pairs.tsv", sep = "\t", quote = FALSE, row.names = FALSE)