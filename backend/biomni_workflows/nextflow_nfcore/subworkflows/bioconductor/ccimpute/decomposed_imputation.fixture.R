# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SingleCellExperiment)

# Construct a synthetic dataset to avoid ExperimentHub fetches (UsoskinBrainData)
set.seed(0)
X <- matrix(rpois(10000, lambda = 1), nrow = 100, ncol = 100)
rownames(X) <- paste0("Gene", 1:100)
colnames(X) <- paste0("Cell", 1:100)

# Simulate labels that match the vignette's filtering logic
labels <- sample(c("NP", "PEP", "NF", "TH", "Empty well", "NF outlier"), 100, replace = TRUE)

# Filter bad cells
filt <- !grepl("Empty well", labels) & !grepl("NF outlier", labels) & !grepl("TH outlier", labels) & !grepl("NoN outlier", labels) & !grepl("NoN", labels) & !grepl("Central, unsolved", labels) & !grepl(">1 cell", labels) & !grepl("Medium", labels)
labels <- labels[filt]
X <- as.matrix(X[, filt])

# Remove genes that are not expressed in any cells:
X <- X[rowSums(X) > 0, ]

# Recreate the SingleCellExperiment and add log-transformed data:
ann <- data.frame(cell_id = labels)
sce <- SingleCellExperiment(assays = list(normcounts = as.matrix(X)), colData = ann)
logcounts(sce) <- log(normcounts(sce) + 1)

# Serialize the object to the declared input file
saveRDS(sce, "sce.rds")