# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("gDNAx", "gDNAinRNAseqData", "TxDb.Hsapiens.UCSC.hg38.knownGene")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(gDNAx)
library(gDNAinRNAseqData)
library(TxDb.Hsapiens.UCSC.hg38.knownGene)

# Retrieve BAM files from the companion data package
bamfiles <- LiYu22subsetBAMfiles()

# Retrieve the TxDb annotation object
txdb <- TxDb.Hsapiens.UCSC.hg38.knownGene

# Serialize the objects to the expected input files
saveRDS(bamfiles, "bamfiles.txt")
saveRDS(txdb, "txdb.txt")