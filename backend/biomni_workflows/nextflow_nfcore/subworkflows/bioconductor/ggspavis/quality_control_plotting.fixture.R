# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ggspavis", "STexampleData", "scater", "SpatialExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(ggspavis)
    library(STexampleData)
    library(scater)
    library(SpatialExperiment)
})

# Attempt to load the dataset from the companion ExperimentData package.
# If it fails due to offline constraints (ExperimentHub fetch), fallback to a mock object.
spe <- tryCatch({
    spe_obj <- Visium_humanDLPFC()
    rownames(spe_obj) <- rowData(spe_obj)$gene_name
    spe_obj
}, error = function(e) {
    counts_mat <- matrix(rpois(1000, 5), nrow = 10, ncol = 100)
    rownames(counts_mat) <- paste0("gene_", 1:10)
    rownames(counts_mat)[1:2] <- c("MT-1", "MT-2") # for mitochondrial subset
    colnames(counts_mat) <- paste0("spot_", 1:100)
    
    coords <- matrix(runif(200), ncol = 2)
    colnames(coords) <- c("x", "y")
    
    row_data <- DataFrame(gene_name = rownames(counts_mat))
    col_data <- DataFrame(in_tissue = rep(TRUE, 100))
    
    SpatialExperiment(
        assays = list(counts = counts_mat),
        spatialCoords = coords,
        rowData = row_data,
        colData = col_data
    )
})

# Calculate library size
colData(spe)$libsize <- colSums(counts(spe))

# Calculate QC metrics using scater
spe <- addPerCellQCMetrics(spe, subsets = list(mito = grepl("(^MT-)|(^mt-)", rowData(spe)$gene_name)))

# Apply QC thresholds
colData(spe)$low_libsize <- colData(spe)$sum < 400 | colData(spe)$detected < 400
colData(spe)$high_mito <- colData(spe)$subsets_mito_percent > 30

# Feature-level QC
rowData(spe)$feature_sum <- rowSums(counts(spe))
rowData(spe)$low_abundance <- rowSums(counts(spe) > 0) < 20

# Serialize the SpatialExperiment object to the expected input file
saveRDS(spe, "spe.rds")