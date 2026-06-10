# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("quantro", "minfi")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(quantro)
library(minfi)

# Reproduce the vignette's data preparation code
# Load the MethylSet object 'flowSorted' from the quantro package
data(flowSorted)

# Compute Beta values from the MethylSet object
p <- getBeta(flowSorted, offset = 100)

# Extract phenotypic data from the MethylSet object
pd <- pData(flowSorted)

# Serialize the 'p' matrix to 'raw_data.matrix'
# The workflow reads this as a matrix with header and row names.
# write.csv ensures comma-separated values, header, and row names as the first column.
write.csv(p, "raw_data.matrix", row.names = TRUE)

# Serialize the 'pd' DataFrame to 'sample_metadata.csv'
# The workflow reads this as a CSV with header and row names.
# write.csv ensures comma-separated values, header, and row names as the first column.
write.csv(pd, "sample_metadata.csv", row.names = TRUE)