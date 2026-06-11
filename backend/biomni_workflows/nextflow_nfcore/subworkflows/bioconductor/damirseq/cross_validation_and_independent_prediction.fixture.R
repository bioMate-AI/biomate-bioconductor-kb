# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DaMiRseq", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DaMiRseq)
library(SummarizedExperiment)

# Load the example SummarizedExperiment object provided by the package
data(SE, package="DaMiRseq")

# Extract the count matrix and covariate data
count_data <- assay(SE)
covariate_data <- as.data.frame(colData(SE))

# Write to the expected input files
write.table(count_data, file="count_data.txt", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)
write.table(covariate_data, file="covariate_data.txt", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)