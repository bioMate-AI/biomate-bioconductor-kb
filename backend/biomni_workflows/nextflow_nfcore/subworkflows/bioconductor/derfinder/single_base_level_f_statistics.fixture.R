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
library("GenomicRanges") # Loaded in vignette, included for completeness

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Create the 'files' object (character vector of paths to bigWig files)
files <- rawFiles(system.file("extdata", "AMY", package = "derfinderData"), samplepatt = "bw", fileterm = NULL)
names(files) <- gsub(".bw", "", names(files))

# Load the 'brainspanPheno' dataset
data("brainspanPheno", package = "derfinderData")

# 2. Serialize objects to declared input files in the exact format the workflow reads

# Save '