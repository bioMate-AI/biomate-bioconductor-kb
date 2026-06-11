# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("trackViewer", "rtracklayer", "GenomicRanges", "TxDb.Hsapiens.UCSC.hg19.knownGene", "org.Hs.eg.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(trackViewer)
library(rtracklayer)
library(GenomicRanges)
library(TxDb.Hsapiens.UCSC.hg19.knownGene)
library(org.Hs.eg.db)

# 1. Reproduce data-preparation for 'methy.bed'
# The vignette reads 'methy.bed' from the package's 'extdata' directory.
# To make this file available in the working directory as an input,
# we copy the original file from the package's 'extdata'.
methy_bed_source_path <- system.file("extdata", "methy.bed", package="trackViewer", mustWork=TRUE)
file.copy(from = methy_bed_source_path, to = "methy.bed", overwrite = TRUE)

# 2. Reproduce data-preparation for 'features.gr'
# The vignette creates a GRanges object named 'gr' which defines a genomic region
# of interest and is used throughout the examples. Given the input file name
# 'features.gr' and the constraint to use exact object names from the vignette,
# 'gr' is the most appropriate object to serialize as 'features.gr'.
gr <- GRanges("chr11", IRanges(122929275, 122930122), strand="-")

# Serialize the 'gr' object to 'features.gr'. Since 'gr' is an S4 object
# (GRanges), 'saveRDS' is the canonical method for serialization.
saveRDS(gr, "features.gr")