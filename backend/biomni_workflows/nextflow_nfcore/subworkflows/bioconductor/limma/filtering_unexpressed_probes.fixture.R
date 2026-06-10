# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("limma")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(limma)

# Generate synthetic data based on standard limma examples
set.seed(123)

# Create a simple expression matrix
y_mat <- matrix(rnorm(100 * 6), nrow = 100, ncol = 6)
rownames(y_mat) <- paste0("Gene", 1:100)
colnames(y_mat) <- paste0("Sample", 1:6)

# Add some differential expression to the first few genes
y_mat[1:5, 4:6] <- y_mat[1:5, 4:6] + 2

# Create a design matrix
group <- factor(rep(c("Control", "Treatment"), each = 3))
design <- model.matrix(~ group)
rownames(design) <- colnames(y_mat)

# Create an EList object (normalized expression object)
y <- new("EList", list(E = y_mat))

# Save objects to the required input files
saveRDS(y, "y.rds")
saveRDS(design, "design.rds")