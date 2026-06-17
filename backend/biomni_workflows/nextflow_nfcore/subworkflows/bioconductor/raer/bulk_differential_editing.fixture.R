# [biomate-fx-deps] self-install the fixture's declared packages on a clean runtime
.fx_deps <- c("raer", "GenomicRanges", "Biostrings", "Rsamtools", "S4Vectors")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GenomicRanges); library(Biostrings); library(Rsamtools); library(S4Vectors)

# Synthesize REAL inputs for raer differential-editing — no package demo data.
# A reference contig + FOUR coordinate-sorted, indexed BAMs (2 Control + 2 Treatment)
# whose reads carry genuine A->G mismatches (RNA editing) at known sites, at a HIGHER
# rate in Treatment than Control, plus the sites GRanges (REF=A, ALT=G). The workflow
# globs *.bam and parses condition from the file name (Control_1 -> Control).
set.seed(42)
L <- 200L
ref <- sample(c("A","C","G","T"), L, replace = TRUE)
sites_pos <- seq(10L, 190L, by = 5L)                    # ~37 sites: DESeq2 needs enough
ref[sites_pos] <- "A"                                   # "genes" to fit the dispersion trend
# Heterogeneous per-site baseline editing rate so the gene-wise dispersions SPREAD (a
# uniform rate makes DESeq2's parametric dispersion fit fail: "all within 2 orders of magnitude").
site_base <- runif(length(sites_pos), 0.03, 0.45)
writeXStringSet(DNAStringSet(c(seq1 = paste(ref, collapse = ""))), "fafn.fasta")

RL <- 50L
rc <- function(s) as.character(reverseComplement(DNAString(s)))
# Emit reads on BOTH strands so any library_type (the workflow uses fr-first-strand, which
# scores +-strand sites from antisense reads) sees coverage with the genuine A->G edit.
emit_bam <- function(sample_name, mult) {
  sam <- c("@HD\tVN:1.6\tSO:coordinate", sprintf("@SQ\tSN:seq1\tLN:%d", L))
  rid <- 0L
  for (start in seq(1L, L - RL, by = 2L)) {
    read <- ref[start:(start + RL - 1L)]
    for (i in seq_along(sites_pos)) {
      s <- sites_pos[i]
      if (s >= start && s < start + RL && runif(1) < min(site_base[i] * mult, 0.95)) read[s - start + 1L] <- "G"
    }
    fwd <- paste(read, collapse = "")
    rid <- rid + 1L
    sam <- c(sam, sprintf("read%dF\t0\tseq1\t%d\t255\t%dM\t*\t0\t0\t%s\t%s",
                          rid, start, RL, fwd, strrep("I", RL)))
    sam <- c(sam, sprintf("read%dR\t16\tseq1\t%d\t255\t%dM\t*\t0\t0\t%s\t%s",
                          rid, start, RL, rc(fwd), strrep("I", RL)))
  }
  samf <- paste0(sample_name, ".sam")
  writeLines(sam, samf)
  asBam(samf, sample_name, overwrite = TRUE)            # -> <sample>.bam + <sample>.bam.bai
  unlink(samf)
  stopifnot(file.exists(paste0(sample_name, ".bam")), file.exists(paste0(sample_name, ".bam.bai")))
}
emit_bam("Control_1",   1.0)   # condition multiplier on the per-site baseline:
emit_bam("Control_2",   1.2)   # Control ~baseline editing,
emit_bam("Treatment_1", 4.0)   # Treatment elevated (differential signal),
emit_bam("Treatment_2", 4.5)   # heterogeneous across sites for dispersion spread.

editing_sites <- GRanges("seq1", IRanges(start = sites_pos, width = 1), strand = "+")
editing_sites$REF <- Rle("A"); editing_sites$ALT <- Rle("G")
saveRDS(editing_sites, "chr_18_editing_sites.gr")
