# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SpaNorm", "SpatialExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SpaNorm)
library(SpatialExperiment)

# Load sample data as shown in the vignette
data("HumanDLPFC", package = "SpaNorm")

# Change gene IDs to gene names
rownames(HumanDLPFC) <- rowData(HumanDLPFC)$gene_name

# Filter genes expressed in 20% of spots
keep <- filterGenes(HumanDLPFC, 0.2)
HumanDLPFC <- HumanDLPFC[keep, ]

# Serialize the SpatialExperiment object to the working directory
saveRDS(HumanDLPFC, "SpatialExperiment.rds")