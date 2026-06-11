# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("derfinder", "derfinderData", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("derfinder")
library("derfinderData")
library("GenomicRanges")

# Load the brainspanPheno data object from the derfinderData package
data(brainspanPheno, package = "derfinderData")

# Serialize brainspanPheno to brainspanPheno.csv
# The workflow reads with row.names = 1, so write row names.
write.csv(brainspanPheno, "brainspanPheno.csv", row.names = TRUE)

# Locate the directory containing the example .bw files within derfinderData
source_bw_dir <- system.file("extdata", "AMY", package = "derfinderData")

# Get the full paths of all .bw files in the source directory
bw_files_full_paths <- list.files(source_bw_dir, pattern = "\\.bw$", full.names = TRUE)

# Copy these .bw files to the current working directory
# The workflow expects these files to be present in the working directory
file.copy(from = bw_files_full_paths, to = ".", overwrite = TRUE)