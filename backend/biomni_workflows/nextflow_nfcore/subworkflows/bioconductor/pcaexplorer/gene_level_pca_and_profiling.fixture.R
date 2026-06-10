# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("airway", "pcaExplorer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(airway)
library(pcaExplorer) # Not strictly needed for data generation, but good practice to include the target package

# Load the example dataset from the airway package
data(airway)

# Extract the count matrix
# The 'airway' object is a DESeqDataSet, from which counts can be extracted
count_matrix <- counts(airway)

# Extract the metadata (coldata)
# Convert the S4 DataFrame to a standard data.frame for writing
metadata <- as.data.frame(colData(airway))

# Write the count matrix to "count_matrix.txt"
# Use tab separator, no quotes, and include row names as the first column
write.table(count_matrix, "count_matrix.txt", sep = "\t", quote = FALSE, col.names = NA)

# Write the metadata to "metadata.txt"
# Use tab separator, no quotes, and include row names as the first column
write.table(metadata, "metadata.txt", sep = "\t", quote = FALSE, col.names = NA)