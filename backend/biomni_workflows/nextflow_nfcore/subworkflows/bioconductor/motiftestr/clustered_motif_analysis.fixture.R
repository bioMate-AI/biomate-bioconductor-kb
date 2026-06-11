# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("motifTestR", "rtracklayer", "BSgenome.Hsapiens.UCSC.hg19")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(motifTestR)
    library(rtracklayer)
    library(BSgenome.Hsapiens.UCSC.hg19)
})

# 1. ex_pfm: List of position frequency matrices
data("ex_pfm", package = "motifTestR")
saveRDS(ex_pfm, file = "ex_pfm")

# 2. test_seq: DNAStringSet of test sequences
data("ar_er_peaks", package = "motifTestR")
test_seq <- getSeq(BSgenome.Hsapiens.UCSC.hg19, ar_er_peaks)
names(test_seq) <- as.character(ar_er_peaks)
saveRDS(test_seq, file = "test_seq")

# 3. rm_seq: DNAStringSet of background sequences
# Generate background sequences by shifting the original peaks
bg_peaks <- shift(ar_er_peaks, 500)
bg_peaks <- trim(bg_peaks)
# Keep only peaks that maintain the original width (400bp) after trimming
valid_idx <- width(bg_peaks) == 400
bg_peaks <- bg_peaks[valid_idx]

rm_seq <- getSeq(BSgenome.Hsapiens.UCSC.hg19, bg_peaks)
names(rm_seq) <- as.character(bg_peaks)
saveRDS(rm_seq, file = "rm_seq")