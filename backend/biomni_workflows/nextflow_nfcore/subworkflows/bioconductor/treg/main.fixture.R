# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TREG", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TREG)
library(SingleCellExperiment)

# Construct a synthetic SingleCellExperiment object matching the structure of the 
# downloaded dataset used in the vignette, as offline generation is required.
set.seed(123)
n_genes <- 1000
n_cells <- 500

# Generate sparse count data
counts <- matrix(rpois(n_genes * n_cells, lambda = 0.5), nrow = n_genes, ncol = n_cells)
counts[sample(length(counts), length(counts) * 0.88)] <- 0
logcounts <- log2(counts + 1)

rownames(counts) <- rownames(logcounts) <- paste0("Gene", seq_len(n_genes))
colnames(counts) <- colnames(logcounts) <- paste0("Cell", seq_len(n_cells))

# Generate cell type annotations matching the vignette's initial cell types
cellType <- sample(
    c("Astro", "Excit_A", "Excit_B", "Inhib_A", "Macrophage", "Micro", "Mural", "Oligo", "OPC", "Tcell"), 
    n_cells, 
    replace = TRUE,
    prob = c(0.1, 0.2, 0.2, 0.1, 0.01, 0.05, 0.01, 0.25, 0.05, 0.03)
)

colData <- S4Vectors::DataFrame(cellType = cellType)

sce.dlpfc.tran <- SingleCellExperiment(
    assays = list(counts = counts, logcounts = logcounts),
    colData = colData
)

# Serialize the object to the declared input file
saveRDS(sce.dlpfc.tran, "sce.dlpfc.tran")