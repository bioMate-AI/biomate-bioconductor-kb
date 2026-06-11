# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("tilingArray")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("tilingArray")

# Load the example data from the package
data("segnf")

# Extract the intensity matrix and genomic coordinates for chromosome 1, positive strand
intensity_mat <- segnf$"1.+"@y
genomic_positions <- segnf$"1.+"@x

# Assign genomic positions as row names
rownames(intensity_mat) <- genomic_positions

# Write the matrix to the required input file
write.table(
    intensity_mat, 
    file = "intensity_matrix.txt", 
    sep = "\t", 
    quote = FALSE, 
    row.names = TRUE, 
    col.names = NA
)