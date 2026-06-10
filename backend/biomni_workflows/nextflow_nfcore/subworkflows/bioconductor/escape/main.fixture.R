# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("escape", "SeuratObject")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(escape)
library(SeuratObject) # Contains the pbmc_small dataset

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# For sc_data.rds:
# The vignette uses 'pbmc_small' from Seurat's example data.
pbmc_small <- get("pbmc_small")

# For gene_sets.rds:
# The vignette uses 'escape.gene.sets' built into the escape package.
data("escape.gene.sets", package="escape")

# 2. Serialize objects to declared input files
saveRDS(pbmc_small, "sc_data.rds")
saveRDS(escape.gene.sets, "gene_sets.rds")