# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ABSSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ABSSeq)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette uses the 'simuN5' dataset.
data(simuN5)

# The 'simuN5' object is a list containing:
# - 'counts': a matrix of gene counts.
# - 'groups': a factor vector defining the experimental groups for each sample.
# - 'DEs': (not used for input files, but part of the dataset)

# 2. Serialize the object to EACH declared input file

# --- Create counts.tsv ---
# The workflow reads counts.tsv using:
# counts_data <- read.table("counts.tsv", header=TRUE, sep="\t", row.names=1, check.names=FALSE)
# This requires a tab-separated file with a header and the first column as row names.
# simuN5$counts is already a matrix suitable for this.
# Convert to data.frame to ensure write.table handles it correctly with row names.
counts_data_fixture <- as.data.frame(simuN5$counts)
write.table(counts_data_fixture, "counts.tsv", sep="\t", quote=FALSE, row.names=TRUE, col.names=TRUE)

# --- Create design_metadata.csv ---
# The workflow reads design_metadata.csv using:
# metadata <- read.csv("design_metadata.csv", header=TRUE, row.names=1, check.names=FALSE)
# This requires a comma-separated file with a header and the first column as row names (sample IDs).
# simuN5$groups is a factor vector. We need to convert it into a data frame
# where row names are sample IDs and there's a column for the group information.
metadata_fixture <- data.frame(groups = simuN5$groups)
# The sample IDs for the metadata should match the column names of the counts matrix.
rownames(metadata_fixture) <- colnames(simuN5$counts)
write.csv(metadata_fixture, "design_metadata.csv", quote=FALSE, row.names=TRUE)