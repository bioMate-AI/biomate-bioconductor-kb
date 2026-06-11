# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("wiggleplotr", "GenomicRanges", "dplyr", "GenomicFeatures", "ensembldb", "EnsDb.Hsapiens.v86", "org.Hs.eg.db", "TxDb.Hsapiens.UCSC.hg38.knownGene")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("wiggleplotr")
library("GenomicRanges")
library("dplyr")
library("GenomicFeatures")
library("ensembldb")
library("EnsDb.Hsapiens.v86")
library("org.Hs.eg.db")
library("TxDb.Hsapiens.UCSC.hg38.knownGene")

# The wiggleplotr package comes with example annotations for the NCOA7 gene pre-loaded
data("ncoa7_exons", package = "wiggleplotr", envir = environment())
data("ncoa7_cdss", package = "wiggleplotr", envir = environment())
data("ncoa7_metadata", package = "wiggleplotr", envir = environment())

# Serialize the objects to the declared input files
saveRDS(ncoa7_exons, "exons_list")
saveRDS(ncoa7_cdss, "cds_list.rds")
saveRDS(ncoa7_metadata, "metadata_df.csv")
saveRDS(EnsDb.Hsapiens.v86, "EnsDb_object.rds")
saveRDS(TxDb.Hsapiens.UCSC.hg38.knownGene, "TxDb_object.rds")