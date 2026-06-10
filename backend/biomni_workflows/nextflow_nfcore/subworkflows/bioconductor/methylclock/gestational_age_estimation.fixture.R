# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("methylclockData", "methylclock", "tibble")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(methylclockData)
library(methylclock)
library(tibble)

# Reproduce the vignette's data-preparation code
TestDataset <- get_TestDataset()

# Construct a synthetic progress_vars tibble matching the samples in TestDataset
# get_TestDataset() returns a data.frame where the first column is typically CpG IDs
cols <- colnames(TestDataset)
if (is.character(TestDataset[[1]]) && any(grepl("^cg", head(TestDataset[[1]])))) {
    sample_names <- cols[-1]
} else {
    sample_names <- cols
}

progress_vars <- tibble(
    sample = sample_names,
    gestational_age = seq(32.0, 41.0, length.out = length(sample_names))
)

# Serialize objects to the declared input files
saveRDS(TestDataset, file = "TestDataset.rds")
saveRDS(progress_vars, file = "progress_vars.rds")