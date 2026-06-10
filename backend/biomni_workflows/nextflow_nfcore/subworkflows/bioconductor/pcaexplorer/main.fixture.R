# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("pcaExplorer", "airway")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(pcaExplorer)
library(airway)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The pcaExplorer vignette (Section 3.2) refers to the 'airway' package dataset
# as the recommended use case. The 'airway' package provides a DESeqDataSet
# object named 'airway'.
data(airway)

# Extract the count matrix from the DESeqDataSet object
count_matrix <- counts(airway)

# Extract the sample metadata (colData) from the DESeqDataSet object
# Convert the S4Vectors::DFrame to a standard data.frame for writing
metadata <- as.data.frame(colData(airway))

# 2. Serialize the objects to EACH declared input file
# The workflow reads "count_matrix.txt" and "metadata.txt" as tab-separated
# files with header and row names.

# Write count_matrix to "count_matrix.txt"
write.table(
  count_matrix,
  file = "count_matrix.txt",
  sep = "\t",
  quote = FALSE,
  row.names = TRUE,
  col.names = TRUE
)

# Write metadata to "metadata.txt"
write.table(
  metadata,
  file = "metadata.txt",
  sep = "\t",
  quote = FALSE,
  row.names = TRUE,
  col.names = TRUE
)