# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("chromVAR", "BSgenome.Hsapiens.UCSC.hg19")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(chromVAR)
library(BSgenome.Hsapiens.UCSC.hg19)

# 1. peaks.bed
peakfile <- system.file("extdata/test_bed.txt", package = "chromVAR")
if (file.exists(peakfile)) {
    file.copy(peakfile, "peaks.bed", overwrite = TRUE)
}

# 2. alignments.bam
bamfile <- system.file("extdata/test_RG.bam", package = "chromVAR")
if (file.exists(bamfile)) {
    file.copy(bamfile, "alignments.bam", overwrite = TRUE)
}

# Copy BAM index if available
bamfile_bai <- system.file("extdata/test_RG.bam.bai", package = "chromVAR")
if (file.exists(bamfile_bai)) {
    file.copy(bamfile_bai, "alignments.bam.bai", overwrite = TRUE)
}

# 3. genome_sequence
# The spec describes it as "BSgenome package matching the alignment genome".
# Serializing the BSgenome object as an RDS file.
saveRDS(BSgenome.Hsapiens.UCSC.hg19, "genome_sequence")