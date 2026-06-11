# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SGSeq", "TxDb.Hsapiens.UCSC.hg19.knownGene", "GenomeInfoDb", "AnnotationDbi")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SGSeq)
library(TxDb.Hsapiens.UCSC.hg19.knownGene)
library(GenomeInfoDb)
library(AnnotationDbi)

# 1. Prepare txdb
txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
txdb <- keepSeqlevels(txdb, "chr16")
seqlevelsStyle(txdb) <- "NCBI"
saveDb(txdb, "txdb")

# 2. Prepare file_bam
path <- system.file("extdata", package = "SGSeq")
bam_file <- file.path(path, "bams", "N1.bam")

if (file.exists(bam_file)) {
    file.copy(bam_file, "file_bam", overwrite = TRUE)
    file.copy(paste0(bam_file, ".bai"), "file_bam.bai", overwrite = TRUE)
} else {
    # Fallback to any available BAM file in the package
    bam_files <- list.files(file.path(path, "bams"), pattern = "\\.bam$", full.names = TRUE)
    if (length(bam_files) > 0) {
        file.copy(bam_files[1], "file_bam", overwrite = TRUE)
        file.copy(paste0(bam_files[1], ".bai"), "file_bam.bai", overwrite = TRUE)
    }
}