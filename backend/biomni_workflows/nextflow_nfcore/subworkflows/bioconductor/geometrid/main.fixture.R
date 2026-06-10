# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("geomeTriD", "trackViewer", "InteractionSet", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(geomeTriD)
library(trackViewer)
library(InteractionSet)
library(GenomicRanges)

# Prepare gi_nij.rds
gi_nij_path <- system.file("extdata", "nij.chr6.51120000.53200000.gi.rds", package = "geomeTriD")
if (file.exists(gi_nij_path)) {
    gi_nij <- readRDS(gi_nij_path)
} else {
    # Fallback synthetic GInteractions object
    gi_nij <- GInteractions(
        GRanges("chr6", IRanges(51120000, 51160000)),
        GRanges("chr6", IRanges(51120000, 51160000)),
        score = 45.1227
    )
}
saveRDS(gi_nij, "gi_nij.rds")

# Prepare ctcf.sample.rds
ctcf_path <- system.file("extdata", "ctcf.sample.rds", package = "trackViewer")
if (file.exists(ctcf_path)) {
    ctcf <- readRDS(ctcf_path)
} else {
    # Fallback synthetic track object
    gr <- GRanges("chr6", IRanges(51188134, 51188334), score = 0.779979)
    ctcf <- new("track", dat = gr, type = "data", format = "BED")
}
saveRDS(ctcf, "ctcf.sample.rds")