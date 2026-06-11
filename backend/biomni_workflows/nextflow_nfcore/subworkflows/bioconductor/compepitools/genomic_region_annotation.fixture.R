# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("compEpiTools", "TxDb.Mmusculus.UCSC.mm9.knownGene", "org.Mm.eg.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(compEpiTools)
require(TxDb.Mmusculus.UCSC.mm9.knownGene)
require(org.Mm.eg.db)

# 1. Reproduce the vignette's data-preparation code

# Create txdb object
txdb <- TxDb.Mmusculus.UCSC.mm9.knownGene

# Create the 'gr' object for user_regions
TSSpos <- TSS(txdb)
user_regions <- TSSpos[1:5]
start(user_regions) <- start(user_regions) - 1000
end(user_regions) <- end(user_regions) - 600
mcols(user_regions) <- NULL

# Load the 'CGIgr_mm9' object for user_annotations
cgipath <- system.file("extdata", "CGIgr_mm9.Rdata", package="compEpiTools")
load(cgipath) # This loads an object named CGIgr_mm9
user_annotations <- CGIgr_mm9

# 2. Serialize objects to the declared input files
save(user_regions, file = "user_regions.RData")
save(user_annotations, file = "user_annotations.RData")