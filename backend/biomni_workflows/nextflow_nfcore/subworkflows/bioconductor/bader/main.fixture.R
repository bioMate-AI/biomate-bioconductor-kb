# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("pasilla")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(pasilla)

# Get the path to the original data file within the 'pasilla' package
datafile_source_path <- system.file("extdata/pasilla_gene_counts.tsv", package="pasilla")

# Read the original data table from the 'pasilla' package
# This creates the 'pasillaCountTable' object as it would be read by the vignette
# The sep="\t" is explicitly added for clarity, matching the workflow's read description.
pasillaCountTable <- read.table(datafile_source_path, header=TRUE, row.names=1, sep="\t")

# Serialize the 'pasillaCountTable' object to the expected input file
# 'pasilla_gene_counts.tsv' in the current working directory.
# The format must match the workflow's read.table call:
# read.table(datafile, header=TRUE, row.names=1, sep="\t")
# For write.table, quote=FALSE prevents quotes around cell values,
# and col.names=NA ensures the row names column has an empty header,
# which is consistent with read.table(row.names=1).
write.table(pasillaCountTable, file="pasilla_gene_counts.tsv", sep="\t", quote=FALSE, col.names=NA)