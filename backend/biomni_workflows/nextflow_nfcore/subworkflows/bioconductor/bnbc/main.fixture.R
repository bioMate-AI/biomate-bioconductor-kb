# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bnbc", "S4Vectors", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bnbc)
library(S4Vectors)
library(GenomicRanges)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
data(cgEx)

# 2. Create the objects corresponding to the input files
# LociData is rowData(cgEx)
LociData <- rowData(cgEx)

# SampleData is colData(cgEx)
SampleData <- colData(cgEx)

# upper.mats.list needs to be derived from contacts(cgEx).
# contacts(cgEx) returns a list of symmetric matrices.
# The workflow expects 'upper.mats.list' to contain matrices where the lower triangle
# will be filled from the upper triangle. To prepare this, we take the symmetric
# matrices from cgEx, and set their lower triangle (excluding the diagonal) to 0.
# The diagonal and upper triangle should remain as they are in the symmetric matrices.
symmetric_mats_list <- contacts(cgEx)

upper.mats.list <- lapply(symmetric_mats_list, function(M) {
  M_upper <- M
  M_upper[lower.tri(M_upper)] <- 0
  M_upper
})

# 3. Serialize the objects to EACH declared input file in the exact format
saveRDS(upper.mats.list, "upper.mats.list")
saveRDS(LociData, "LociData.rds")
saveRDS(SampleData, "SampleData.rds")

# Also save with .rds extension as the workflow checks for both
saveRDS(upper.mats.list, "upper.mats.list")
saveRDS(LociData, "LociData.rds")
saveRDS(SampleData, "SampleData.rds")