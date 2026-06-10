# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CiteFuse")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CiteFuse)

# Reproduce the vignette's data-preparation code
data("CITEseq_example", package = "CiteFuse")

# Extract the matrices
rna_mat <- CITEseq_example$RNA
adt_mat <- CITEseq_example$ADT
hto_mat <- CITEseq_example$HTO

# Serialize matrices to the specified input files in a format readable by the workflow
# Using whitespace-delimited format with header and row names, matching read.table(..., sep="", header=TRUE, row.names=1)
write.table(rna_mat, file = "RNA_counts.matrix", sep = " ", quote = FALSE, col.names = NA)
write.table(adt_mat, file = "ADT_counts.matrix", sep = " ", quote = FALSE, col.names = NA)
write.table(hto_mat, file = "HTO_counts.matrix", sep = " ", quote = FALSE, col.names = NA)