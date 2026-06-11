# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("motifTestR", "BSgenome.Hsapiens.UCSC.hg19")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(motifTestR)
library(BSgenome.Hsapiens.UCSC.hg19)

data("ar_er_peaks", package = "motifTestR")
data("ex_pfm", package = "motifTestR")

saveRDS(ar_er_peaks, "ar_er_peaks.rds")
saveRDS(BSgenome.Hsapiens.UCSC.hg19, "BSgenome.Hsapiens.UCSC.hg19.rds")
saveRDS(ex_pfm, "ex_pfm.rds")