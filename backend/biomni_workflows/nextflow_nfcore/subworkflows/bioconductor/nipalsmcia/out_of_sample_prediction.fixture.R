# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("nipalsMCIA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(nipalsMCIA)

# Load the dataset from the package
data(NCI60)

# The dataset provides `data_blocks` (list of matrices) and `metadata_NCI60` (data.frame)
# We will split these into train and test sets to satisfy the required input files.
# There are 21 samples in total. We'll use the first 15 for training and the rest for testing.
train_idx <- 1:15
test_idx <- 16:21

# Split data blocks
data_blocks_train <- lapply(data_blocks, function(x) x[train_idx, , drop = FALSE])
data_blocks_test <- lapply(data_blocks, function(x) x[test_idx, , drop = FALSE])

# Split metadata
metadata_train <- metadata_NCI60[train_idx, , drop = FALSE]
metadata_test <- metadata_NCI60[test_idx, , drop = FALSE]

# Serialize to the required input files
saveRDS(data_blocks_train, "data_blocks_train.rds")
saveRDS(data_blocks_test, "data_blocks_test.rds")
saveRDS(metadata_train, "metadata_train.rds")
saveRDS(metadata_test, "metadata_test.rds")