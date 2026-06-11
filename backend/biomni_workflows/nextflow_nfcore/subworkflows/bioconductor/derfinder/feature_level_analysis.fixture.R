# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("derfinder", "derfinderData", "GenomicRanges", "DESeq2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("derfinder")
library("derfinderData")
library("GenomicRanges")
library("DESeq2")

# Reproduce data-preparation code for 'fullCov'
# Using the more complete call from Section 4 of the vignette
files <- rawFiles(system.file("extdata", "AMY", package = "derfinderData"), samplepatt = "bw", fileterm = NULL )
names(files) <- gsub(".bw", "", names(files))
fullCov <- fullCoverage( files = files, chrs = "chr21", verbose = FALSE, totalMapped = rep(1, length(files)), targetSize = 1 )

# Reproduce data-preparation code for 'genomicState'
# The provided vignette