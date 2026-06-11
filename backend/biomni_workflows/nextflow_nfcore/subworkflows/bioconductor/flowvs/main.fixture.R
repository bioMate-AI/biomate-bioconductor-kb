# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("flowVS", "vsn", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(flowVS)
library(vsn)
library(Biobase)

# Load the kidney microarray dataset used in the vignette
data(kidney, package="vsn")

# Extract expression matrix
counts <- exprs(kidney)

# Extract phenotype data
coldata <- pData(kidney)
if (nrow(coldata) == 0 || is.null(coldata)) {
    coldata <- data.frame(Sample = colnames(counts), row.names = colnames(counts))
}

# Write to expected input files
write.csv(counts, "counts.csv", row.names = TRUE)
write.csv(coldata, "coldata.csv", row.names = TRUE)