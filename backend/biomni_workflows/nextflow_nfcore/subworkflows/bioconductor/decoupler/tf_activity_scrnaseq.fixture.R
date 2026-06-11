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

# Reproduce the vignette's data preparation
data <- get_toy_data()
mat <- data$mat

# The workflow expects a Seurat object containing normalized log-transformed counts.
# We construct it using the toy matrix from decoupleR.
sc_data <- CreateSeuratObject(counts = mat)
sc_data <- NormalizeData(sc_data, verbose = FALSE)

# Serialize the object to the declared input file
saveRDS(sc_data, "sc_data.rds")