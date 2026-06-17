# [biomate-fx-deps] self-install the fixture's declared packages on a clean runtime
.fx_deps <- c("raer", "GenomicRanges", "Biostrings", "Rsamtools", "S4Vectors")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GenomicRanges); library(Biostrings); library(Rsamtools); library(S4Vectors)

# Synthesize REAL inputs for raer::calc_AEI() (Alu Editing Index) — no package demo data.
# A reference contig + an indexed BAM whose reads carry genuine A->G mismatches inside a
# defined "Alu" region, plus the alus.gr (regions to score) and alu_snps.gr (positions to
# exclude). The workflow reads bam_files.bam, fafn.fasta, alus.gr, alu_snps.gr.
set.seed(42)
L <- 300L
ref <- sample(c("A","C","G","T"), L, replace = TRUE)
alu_start <- 60L; alu_end <- 200L
# Make the Alu region A-rich so calc_AEI has many reference-A positions to score.
ref[alu_start:alu_end][runif(alu_end - alu_start + 1L) < 0.6] <- "A"
writeXStringSet(DNAStringSet(c(seq1 = paste(ref, collapse = ""))), "fafn.fasta")

RL <- 50L
sam <- c("@HD\tVN:1.6\tSO:coordinate", sprintf("@SQ\tSN:seq1\tLN:%d", L))
rid <- 0L
for (start in seq(1L, L - RL, by = 2L)) {
  rid <- rid + 1L
  read <- ref[start:(start + RL - 1L)]
  for (i in seq_along(read)) {                            # A->G editing within the Alu region
    gpos <- start + i - 1L
    if (read[i] == "A" && gpos >= alu_start && gpos <= alu_end && runif(1) < 0.5) read[i] <- "G"
  }
  sam <- c(sam, sprintf("read%d\t0\tseq1\t%d\t255\t%dM\t*\t0\t0\t%s\t%s",
                        rid, start, RL, paste(read, collapse = ""), strrep("I", RL)))
}
writeLines(sam, "reads.sam")
asBam("reads.sam", "bam_files", overwrite = TRUE)         # -> bam_files.bam + bam_files.bam.bai
unlink("reads.sam")
stopifnot(file.exists("bam_files.bam"), file.exists("bam_files.bam.bai"))

alus <- GRanges("seq1", IRanges(start = alu_start, end = alu_end), strand = "+")
saveRDS(alus, "alus.gr")
alu_snps <- GRanges("seq1", IRanges(start = c(70L, 90L, 110L), width = 1), strand = "+")
saveRDS(alu_snps, "alu_snps.gr")
