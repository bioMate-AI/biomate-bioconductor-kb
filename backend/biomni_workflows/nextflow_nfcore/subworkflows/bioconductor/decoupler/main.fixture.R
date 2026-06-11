# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("decoupleR", "Seurat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(decoupleR)
library(Seurat)

# Extract toy data provided by the decoupleR package
toy_data <- get_toy_data()
mat <- toy_data$mat

# The toy matrix contains continuous values. 
# To create a valid Seurat object with raw counts, we transform it to non-negative integers.
counts_mat <- round(exp(mat))
counts_mat[counts_mat < 0] <- 0

# Create the Seurat object
sc_data <- CreateSeuratObject(counts = counts_mat)

# Normalize the data to provide the required normalized log-transformed counts
sc_data <- NormalizeData(sc_data, verbose = FALSE)

# Serialize to the expected input file
saveRDS(sc_data, "sc_data.rds")