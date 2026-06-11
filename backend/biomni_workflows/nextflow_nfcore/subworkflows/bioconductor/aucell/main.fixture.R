# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AUCell", "GSEABase", "Matrix")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AUCell)
library(GSEABase)
library(Matrix)

# 1. Generate geneSets using the package's example GMT file
gmtFile <- file.path(system.file('examples', package='AUCell'), "geneSignatures.gmt")
if (file.exists(gmtFile)) {
    geneSets <- getGmt(gmtFile)
} else {
    # Fallback synthetic GeneSetCollection if the file is missing
    geneSets <- GeneSetCollection(
        GeneSet(c("gene1", "gene2", "gene3"), setName="geneSet1")
    )
}

# 2. Generate exprMatrix
# Extract genes from geneSets to ensure they overlap with exprMatrix
all_genes <- unique(unlist(geneIds(geneSets)))
if (length(all_genes) == 0) {
    all_genes <- paste0("gene", 1:100)
}
# Add some random genes to make the matrix realistic
all_genes <- unique(c(all_genes, paste0("Gene", 1:1000)))

set.seed(123)
# Create a synthetic sparse expression matrix (genes x cells)
mat <- matrix(rpois(length(all_genes) * 100, lambda = 1), nrow = length(all_genes), ncol = 100)
rownames(mat) <- all_genes
colnames(mat) <- paste0("Cell", 1:100)
exprMatrix <- as(mat, "dgCMatrix")

# 3. Serialize objects to the declared input files
saveRDS(exprMatrix, "exprMatrix.rds")
saveRDS(geneSets, "geneSets.rds")