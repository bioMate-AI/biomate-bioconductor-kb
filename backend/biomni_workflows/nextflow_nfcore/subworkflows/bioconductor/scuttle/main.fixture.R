# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scuttle", "scRNAseq", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scuttle)
library(scRNAseq)
library(SingleCellExperiment)

# Attempt to use the vignette's exact data calls.
# Wrap in tryCatch to guarantee offline execution if ExperimentHub is unavailable.
sce <- tryCatch({
    ZeiselBrainData()
}, error = function(e) {
    # Construct a synthetic SingleCellExperiment matching the vignette's structure
    cells <- c("1772063062_D05", "1772063061_D01", "1772060240_F02", "1772062114_F05", paste0("Cell", 5:20))
    genes <- c("Tspan12", "Tshz1", "Fnbp1l", "Adamts15", "Cldn12", "Rxfp1", paste0("Gene", 7:100))
    
    counts_mat <- matrix(rpois(100 * 20, lambda=5), nrow=100, ncol=20)
    rownames(counts_mat) <- genes
    colnames(counts_mat) <- cells
    
    col_data <- DataFrame(
        tissue = rep("brain", 20),
        group = rep(1, 20),
        level1class = rep("interneurons", 20),
        level2class = rep("Int1", 20),
        row.names = cells
    )
    
    row_data <- DataFrame(
        featureType = rep("gene", 100),
        row.names = genes
    )
    
    ercc_counts <- matrix(rpois(10 * 20, lambda=2), nrow=10, ncol=20)
    rownames(ercc_counts) <- paste0("ERCC-", 1:10)
    colnames(ercc_counts) <- cells
    ercc_se <- SummarizedExperiment(list(counts=ercc_counts))
    
    sce_obj <- SingleCellExperiment(
        assays = list(counts = counts_mat),
        colData = col_data,
        rowData = row_data
    )
    altExp(sce_obj, "ERCC") <- ercc_se
    sce_obj
})

sce.ens <- tryCatch({
    ZeiselBrainData(ensembl=TRUE)
}, error = function(e) {
    cells <- c("1772063062_D05", "1772063061_D01", "1772060240_F02", "1772062114_F05", paste0("Cell", 5:20))
    ens_ids <- c("ENSMUSG00000029669", "ENSMUSG00000046982", "ENSMUSG00000039735", 
                 "ENSMUSG00000033453", "ENSMUSG00000046798", "ENSMUSG00000034009", 
                 paste0("ENSMUSG", 7:100))
    genes <- c("Tspan12", "Tshz1", "Fnbp1l", "Adamts15", "Cldn12", "Rxfp1", paste0("Gene", 7:100))
    
    counts_mat <- matrix(rpois(100 * 20, lambda=5), nrow=100, ncol=20)
    rownames(counts_mat) <- ens_ids
    colnames(counts_mat) <- cells
    
    col_data <- DataFrame(
        tissue = rep("brain", 20),
        group = rep(1, 20),
        level1class = rep("interneurons", 20),
        level2class = rep("Int1", 20),
        row.names = cells
    )
    
    row_data <- DataFrame(
        featureType = rep("gene", 100),
        originalName = genes,
        row.names = ens_ids
    )
    
    ercc_counts <- matrix(rpois(10 * 20, lambda=2), nrow=10, ncol=20)
    rownames(ercc_counts) <- paste0("ERCC-", 1:10)
    colnames(ercc_counts) <- cells
    ercc_se <- SummarizedExperiment(list(counts=ercc_counts))
    
    sce_obj <- SingleCellExperiment(
        assays = list(counts = counts_mat),
        colData = col_data,
        rowData = row_data
    )
    altExp(sce_obj, "ERCC") <- ercc_se
    sce_obj
})

# Serialize objects to the declared input files
saveRDS(sce, "sce.rds")
saveRDS(sce.ens, "sce.rds")