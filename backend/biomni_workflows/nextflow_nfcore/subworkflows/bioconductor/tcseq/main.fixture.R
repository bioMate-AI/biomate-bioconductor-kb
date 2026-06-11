# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TCseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TCseq)

# 1. Reproduce the vignette's data-preparation code
data("genomicIntervals")
data("experiment")
data("countsTable")

# 2. Serialize objects to input files in the exact format the workflow reads

# experiment_design.txt: read with header = TRUE, tab-separated
write.table(experiment, "experiment_design.txt", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)

# genomic_intervals.bed: read with header = FALSE, tab-separated
write.table(genomicIntervals, "genomic_intervals.bed", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# counts_table.txt: read with row.names = 1, header = TRUE, tab-separated
write.table(countsTable, "counts_table.txt", sep = "\t", row.names = TRUE, col.names = TRUE, quote = FALSE)