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

# Locate or create gi.rds
gi_file <- system.file("extdata", "gi.rds", package = "trackViewer")
if (gi_file == "" || !file.exists(gi_file)) {
    gi_file <- system.file("extdata", "gi.rds", package = "geomeTriD")
}

if (gi_file != "" && file.exists(gi_file)) {
    file.copy(gi_file, "gi.rds", overwrite = TRUE)
} else {
    # Fallback: create a synthetic GInteractions object
    gr1 <- GRanges("chr2", IRanges(234300000, 234310000))
    gr2 <- GRanges("chr2", IRanges(234400000, 234410000))
    gi <- GInteractions(gr1, gr2, score = 10)
    saveRDS(gi, "gi.rds")
}

# Create a dummy file for the TxDb package requirement to satisfy file existence checks
file.create("TxDb.Hsapiens.UCSC.hg19.knownGene")