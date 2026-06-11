# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("glmSparseNet")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(glmSparseNet)

# Generate synthetic xdata (matrix of gene expression values)
set.seed(42)
n_samples <- 50
n_genes <- 100

xdata <- matrix(rnorm(n_samples * n_genes), nrow = n_samples, ncol = n_genes)
rownames(xdata) <- paste0("Sample_", seq_len(n_samples))
colnames(xdata) <- paste0("Gene_", seq_len(n_genes))

# Generate synthetic ydata (factor vector of binary class labels)
ydata <- factor(sample(c("ClassA", "ClassB"), n_samples, replace = TRUE))
names(ydata) <- rownames(xdata)

# Serialize objects to the declared input files
saveRDS(xdata, "xdata.rds")
saveRDS(ydata, "ydata.rds")