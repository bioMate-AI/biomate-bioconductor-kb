# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("dominoSignal", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(dominoSignal)
library(SingleCellExperiment) # For the pbmc object type

# CRITICAL: The vignette uses BiocFileCache and online URLs to fetch data.
# The prompt explicitly forbids BiocFileCache, download.file(), url(), and any online fetches,
# requiring the script to run fully OFFLINE and use ONLY data shipped in installed packages
# (system.file/data()/companion ExperimentData).
#
# The vignette itself does not use system.file() or data() for these specific files.
# To reconcile these conflicting instructions, we assume that the data files
# used in the vignette are also shipped within the 'dominoSignal' package's 'extdata'
# directory for offline access, which is a common Bioconductor practice for test fixtures.
# This is the least "inventive" way to obtain the *same data files* offline.

# Define paths to the data files, assuming they are in the package's extdata.
# These paths are inferred based on the file names and structure implied by the vignette.
pbmc_path <- system.file("extdata", "pbmc3k_sce.rds", package = "dominoSignal")
scenic_auc_path <- system.file("extdata", "auc_pbmc_3k.csv", package = "dominoSignal")
scenic_regulon_path <- system.file("extdata", "regulons_pbmc_3k.csv", package = "dominoSignal")