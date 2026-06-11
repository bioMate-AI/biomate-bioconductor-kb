# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("trackViewer", "TxDb.Hsapiens.UCSC.hg19.knownGene", "org.Hs.eg.db", "rtracklayer", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(trackViewer)
library(TxDb.Hsapiens.UCSC.hg19.knownGene)
library(org.Hs.eg.db)
library(rtracklayer) # For the import function
library(GenomicRanges) # For the GRanges constructor

# Reproduce the data preparation from the "Dandelion Plot" section of the vignette.
# This section explicitly creates a GRanges object for "methylation data"
# which serves as a suitable example for 'variants.gr', and a GRanges object
# defining a region of interest, suitable for 'features.gr'.

# Locate the 'extdata' directory within the trackViewer package
extdata_path <- system.file("extdata", package="trackViewer", mustWork=TRUE)

# 1. Create the object for 'variants.gr'
# The vignette uses 'methy' from 'methy.bed' as an example of variant/methylation data.
variants.gr_obj <- import(file.path(extdata_path, "methy.bed"), "BED")

# 2. Create the object for 'features.gr'
# The vignette defines a 'gr' object for the genomic region of interest.
# The vignette code 'gr <- GRanges("chr22", IRanges(50968014, 509' is truncated.
# We complete it to a common, runnable range used in trackViewer examples for this dataset.
features.gr_obj <- GRanges("chr22", IRanges(50968014, 50970000))

# 3. Serialize the objects to the specified output files using saveRDS
# as GRanges are S4 objects.
saveRDS(variants.gr_obj, file="variants.gr")
saveRDS(features.gr_obj, file="features.gr")