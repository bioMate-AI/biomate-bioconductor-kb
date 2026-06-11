# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("miloR", "SingleCellExperiment", "scater", "scran", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(miloR)
library(SingleCellExperiment)
library(scater)
library(scran)
library(dplyr)

# 2 Load data
data("sim_trajectory", package = "miloR")
traj_sce <- sim_trajectory[['SCE']]
traj_meta <- sim_trajectory[["meta"]]
colData(traj_sce) <- DataFrame(traj_meta)
colnames(traj_sce) <- colData(traj_sce)$cell_id
redim <- reducedDim(traj_sce, "PCA")
dimnames(redim) <- list(colnames(traj_sce), paste0("PC", c(1:50)))
reducedDim(traj_sce, "PCA") <- redim

# 3 Pre-processing
logcounts(traj_sce) <- log(counts(traj_sce) + 1)
traj_sce <- runPCA(traj_sce, ncomponents=30)
traj_sce <- runUMAP(traj_sce)

# 4 Create a Milo object
traj_milo <- Milo(traj_sce)
reducedDim(traj_milo, "UMAP") <- reducedDim(traj_sce, "UMAP")

# 5 Construct KNN graph
traj_milo <- buildGraph(traj_milo, k = 10, d = 30)

# 6 Defining representative neighbourhoods
traj_milo <- makeNhoods(traj_milo, prop = 0.1, k = 10, d=30, refined = TRUE)

# 7 Counting cells in neighbourhoods
traj_milo <- countCells(traj_milo, meta.data = data.frame(colData(traj_milo)), samples="Sample")

# 8 Differential abundance testing - prepare traj_design
traj_design <- data.frame(colData(traj_milo))[,c("Sample", "Condition")]
traj_design <- distinct(traj_design)
rownames(traj_design) <- traj_design$Sample
traj_design <- traj_design[colnames(nhoodCounts(traj_milo)), , drop=FALSE]

# Serialize the objects to the declared input files
saveRDS(traj_milo, "embryo_data.rds")
saveRDS(traj_design, "embryo_design.rds")