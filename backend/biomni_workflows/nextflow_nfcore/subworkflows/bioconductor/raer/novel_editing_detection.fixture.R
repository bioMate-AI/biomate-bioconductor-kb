# [biomate] structured fixture (synthetic, deterministic) — no package demo data.
# novel_editing_detection hardcodes contig "chr4", so every track is synthesized ON chr4 and
# kept mutually consistent: an indexed BAM with genuine A->G edits (both strands, so the
# fr-first-strand library_type scores them), a matching reference FASTA, a TxDb, a SNP
# GRanges (to exclude) and a RepeatMasker GRanges (the de-novo search region).
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
for (.dp in c("GenomicFeatures", "txdbmaker", "GenomicRanges", "Biostrings", "Rsamtools")) {
  if (!requireNamespace(.dp, quietly=TRUE)) {
    bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
    tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e2) NULL))
  }
}
suppressMessages({library(GenomicRanges); library(Biostrings); library(Rsamtools)})

CHR <- "chr4"
set.seed(1)
L <- 500L
ref <- sample(c("A","C","G","T"), L, replace = TRUE)
sites_pos <- c(100L, 150L, 200L, 250L, 300L)
ref[sites_pos] <- "A"                                   # reference A at every editing site
writeXStringSet(DNAStringSet(setNames(paste(ref, collapse = ""), CHR)), "fasta.fasta")
indexFa("fasta.fasta")

# --- bams.bam : indexed BAM, both strands, A->G edits at the sites -------------------------
RL <- 50L
rc <- function(s) as.character(reverseComplement(DNAString(s)))
sam <- c("@HD\tVN:1.6\tSO:coordinate", sprintf("@SQ\tSN:%s\tLN:%d", CHR, L))
rid <- 0L
for (start in seq(1L, L - RL, by = 3L)) {
  read <- ref[start:(start + RL - 1L)]
  for (s in sites_pos) {
    if (s >= start && s < start + RL && runif(1) < 0.6) read[s - start + 1L] <- "G"
  }
  fwd <- paste(read, collapse = "")
  rid <- rid + 1L
  sam <- c(sam, sprintf("r%dF\t0\t%s\t%d\t255\t%dM\t*\t0\t0\t%s\t%s",  rid, CHR, start, RL, fwd,     strrep("I", RL)),
                sprintf("r%dR\t16\t%s\t%d\t255\t%dM\t*\t0\t0\t%s\t%s", rid, CHR, start, RL, rc(fwd), strrep("I", RL)))
}
writeLines(sam, "reads.sam")
asBam("reads.sam", "bams", overwrite = TRUE)            # -> bams.bam + bams.bam.bai
unlink("reads.sam")
stopifnot(file.exists("bams.bam"), file.exists("bams.bam.bai"))

# --- txdb.sqlite : a TxDb (loadDb-compatible) on chr4 --------------------------------------
.mkTxDb <- if (requireNamespace("txdbmaker", quietly=TRUE)) txdbmaker::makeTxDbFromGRanges else GenomicFeatures::makeTxDbFromGRanges
.txdb <- .mkTxDb(GRanges(CHR, IRanges(start = 50, end = 450), strand = "+", type = "exon", Parent = "tx1"))
AnnotationDbi::saveDb(.txdb, "txdb.sqlite")

# --- chr4snps.gr : SNPs to exclude (between sites, so they don't mask the edits) -----------
saveRDS(GRanges(CHR, IRanges(start = c(120L, 170L, 270L), width = 1), strand = "+"), "chr4snps.gr")
# --- rmsk_hg38.gr : the repeat region searched for de-novo editing (covers the sites) ------
saveRDS(GRanges(CHR, IRanges(start = 50L, end = 450L), strand = "+"), "rmsk_hg38.gr")
