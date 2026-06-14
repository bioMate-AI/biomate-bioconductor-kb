# [biomate] structured fixture (rule: package_example_data + valid serializers) — deterministic
# This workflow reads FIVE real inputs by exact name:
#   bams.bam        — indexed BAM alignments
#   fasta.fasta     — reference genome FASTA (indexed)
#   txdb.sqlite     — a TxDb SQLite database loaded with loadDb()  (NOT a plain RDS!)
#   chr4snps.gr     — a serialized GRanges (readRDS)
#   rmsk_hg38.gr    — a serialized GRanges (readRDS)
# The previous fixture only emitted bams.bam + fasta.fasta, so loadDb("txdb.sqlite") hit
# "file is not a database" and the two .gr GRanges were missing. Emit ALL FIVE with the
# correct on-disk format (saveDb for the TxDb, saveRDS for the GRanges), all consistent
# with the BAM's reference sequence so raer's pileup runs.
suppressMessages({if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")})
for (.dp in c("GenomicFeatures", "txdbmaker", "GenomicRanges", "Biostrings", "Rsamtools",
              "pasillaBamSubset")) {
  if (!requireNamespace(.dp, quietly=TRUE)) tryCatch(BiocManager::install(.dp, update=FALSE, ask=FALSE), error=function(e) NULL)
}
suppressMessages({
  library(GenomicRanges); library(Biostrings); library(Rsamtools)
})

# --- bams.bam : copy a real indexed example BAM -------------------------------------------
.bam_src <- NA_character_
for (.dp in c("pasillaBamSubset", "Rsamtools")) {
  .d <- system.file("extdata", package=.dp)
  if (nzchar(.d)) {
    .f <- list.files(.d, pattern="(?i)\\.bam$", recursive=TRUE, full.names=TRUE)
    if (length(.f)) { .bam_src <- .f[[1]]; break }
  }
}
stopifnot("no example BAM found"=!is.na(.bam_src))
file.copy(.bam_src, "bams.bam", overwrite=TRUE)
.bai <- paste0(.bam_src, ".bai")
if (file.exists(.bai)) file.copy(.bai, "bams.bam.bai", overwrite=TRUE) else indexBam("bams.bam")

# Discover the BAM's seqnames so the FASTA / TxDb / GRanges all agree with it.
.hdr  <- scanBamHeader("bams.bam")[[1]]
.slen <- .hdr$targets                 # named integer vector: seqname -> length
stopifnot("BAM has no reference sequences"=length(.slen) > 0)
.chr  <- names(.slen)[1]
.len  <- as.integer(.slen[[1]])

# --- fasta.fasta : a real reference whose seqnames/lengths match the BAM --------------------
set.seed(1)
.seq <- DNAStringSet(setNames(
  paste0(sample(c("A","C","G","T"), .len, replace=TRUE), collapse=""), .chr))
writeXStringSet(.seq, "fasta.fasta")
indexFa("fasta.fasta")

# --- txdb.sqlite : a REAL TxDb database written with saveDb (loadDb-compatible) -------------
.mkTxDb <- if (requireNamespace("txdbmaker", quietly=TRUE)) txdbmaker::makeTxDbFromGRanges else GenomicFeatures::makeTxDbFromGRanges
.txdb <- .mkTxDb(GRanges(.chr, IRanges(start=2, end=min(.len - 1L, 1000L)), strand="+",
                         type="exon", Parent="tx1"))
AnnotationDbi::saveDb(.txdb, "txdb.sqlite")

# --- chr4snps.gr / rmsk_hg38.gr : serialized GRanges (readRDS) ------------------------------
.snps <- GRanges(.chr, IRanges(start=c(5, 15, 25), width=1), strand="+")
saveRDS(.snps, "chr4snps.gr")
.rmsk <- GRanges(.chr, IRanges(start=c(50, 150), end=c(80, 200)), strand="+")
saveRDS(.rmsk, "rmsk_hg38.gr")
