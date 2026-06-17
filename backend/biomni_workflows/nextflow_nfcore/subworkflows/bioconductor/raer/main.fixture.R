# [biomate-fx-deps] self-install the fixture's declared packages on a clean runtime
.fx_deps <- c("raer", "GenomicRanges", "Biostrings", "Rsamtools", "S4Vectors")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GenomicRanges); library(Biostrings); library(Rsamtools); library(S4Vectors)

# Synthesize REAL inputs for raer::pileup_cells() (single-cell RNA editing) — no demo data.
# A coordinate-sorted, indexed BAM whose reads carry CB (cell barcode) + UB (UMI) tags and
# genuine A->G mismatches at known sites, plus editing_sites.gr (the .nf adds REF/ALT).
set.seed(42)
L <- 200L
ref <- sample(c("A","C","G","T"), L, replace = TRUE)
sites_pos <- c(10L, 20L, 30L, 40L, 50L)
ref[sites_pos] <- "A"
RL <- 60L
cells <- paste0("CELL_", 1:8)            # >4 so the .nf "edited in >=5 cells" filter can pass

reads <- list(); rid <- 0L; umi <- 0L
for (cell in cells) {
  for (start in seq(1L, L - RL, by = 6L)) {
    read <- ref[start:(start + RL - 1L)]
    for (s in sites_pos) {
      if (s >= start && s < start + RL && runif(1) < 0.5) read[s - start + 1L] <- "G"
    }
    rid <- rid + 1L; umi <- umi + 1L
    reads[[length(reads) + 1L]] <- list(
      start = start,
      line  = sprintf("r%d\t0\tseq1\t%d\t255\t%dM\t*\t0\t0\t%s\t%s\tCB:Z:%s\tUB:Z:U%08d",
                      rid, start, RL, paste(read, collapse = ""), strrep("I", RL), cell, umi))
  }
}
ord <- order(vapply(reads, function(x) x$start, integer(1)))
sam <- c("@HD\tVN:1.6\tSO:coordinate", sprintf("@SQ\tSN:seq1\tLN:%d", L),
         vapply(reads[ord], function(x) x$line, character(1)))
writeLines(sam, "reads.sam")
asBam("reads.sam", "bamfile", overwrite = TRUE)          # -> bamfile.bam + bamfile.bam.bai
unlink("reads.sam")
stopifnot(file.exists("bamfile.bam"), file.exists("bamfile.bam.bai"))

editing_sites <- GRanges("seq1", IRanges(start = sites_pos, width = 1), strand = "+")
saveRDS(editing_sites, "editing_sites.gr")
