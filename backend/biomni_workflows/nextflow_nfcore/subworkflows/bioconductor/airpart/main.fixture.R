# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("airpart", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(airpart)
suppressPackageStartupMessages(library(SingleCellExperiment))

# Simulation set-up
p.vec <- rep(c(0.2, 0.8, 0.5, 0.5, 0.7, 0.9), each = 2)
set.seed(2021)
sce <- makeSimulatedData(mu1 = 2, mu2 = 10, nct = 4, n = 20, ngenecl = 25, theta = 20, ncl = 3, p.vec = p.vec)

# Create allelic ratio matrix
sce <- preprocess(sce)

# QC on cells
cellQCmetrics <- cellQC(sce, mad_detected = 4)
keep_cell <- (cellQCmetrics$filter_sum | # sufficient features (genes)
                cellQCmetrics$filter_detected | # sufficient molecules counted
                # sufficient features expressed compared to spike genes,
                # high quality cells
                cellQCmetrics$filter_spike)
sce <- sce[, keep_cell]

# QC on genes
featureQCmetric <- featureQC(sce)
keep_feature <- (featureQCmetric$filter_celltype & featureQCmetric$filter_sd & featureQCmetric$filter_spike)
sce <- sce[keep_feature, ]

# Gene clustering
sce <- geneCluster(sce, G = 1:4)

# Save the SingleCellExperiment object
saveRDS(sce, "sce.rds")