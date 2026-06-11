# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SGSeq", "TxDb.Hsapiens.UCSC.hg19.knownGene", "GenomeInfoDb", "GenomicRanges", "BSgenome.Hsapiens.UCSC.hg19")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SGSeq)
library(TxDb.Hsapiens.UCSC.hg19.knownGene)
library(GenomeInfoDb)
library(GenomicRanges)
library(BSgenome.Hsapiens.UCSC.hg19)

# 1. file_bam: Indexed BAM files from splice-aware aligner
bam_dir <- system.file("extdata", "bams", package = "SGSeq")
bam_files <- list.files(bam_dir, pattern = "\\.bam$", full.names = TRUE)
bai_files <- list.files(bam_dir, pattern = "\\.bai$", full.names = TRUE)

# Copy BAMs and their indices to the working directory
file.copy(bam_files, basename(bam_files))
file.copy(bai_files, basename(bai_files))

# Serialize the vector of BAM filenames to 'file_bam'
file_bam <- basename(bam_files)
saveRDS(file_bam, "file_bam.rds")

# 2. gr: GRanges object of genomic region of interest (FBXO31 gene locus)
gr <- GRanges("16", IRanges(87349429, 87367727), strand = "-")
saveRDS(gr, "gr.rds")

# 3. txdb: TxDb annotation object for annotating predicted features
txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
txdb <- keepSeqlevels(txdb, "chr16")
seqlevelsStyle(txdb) <- "NCBI"
saveRDS(txdb, "txdb.rds")

# 4. Hsapiens: BSgenome object for variant effect prediction
Hsapiens <- BSgenome.Hsapiens.UCSC.hg19
saveRDS(Hsapiens, "Hsapiens.rds")