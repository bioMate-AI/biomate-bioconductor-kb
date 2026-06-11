# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("gatom")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(gatom)

# Load the example datasets provided by the package
data("gene.de.rawEx", package = "gatom")
data("met.de.rawEx", package = "gatom")

# Serialize the objects to the declared input files as tab-separated tables
write.table(gene.de.rawEx, file = "gene.de.rawEx", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(met.de.rawEx, file = "met.de.rawEx", sep = "\t", row.names = FALSE, quote = FALSE)