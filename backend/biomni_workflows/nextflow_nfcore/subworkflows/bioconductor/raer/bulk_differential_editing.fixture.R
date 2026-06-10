# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("raer", "GenomicRanges", "Biostrings", "Rsamtools", "S4Vectors")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(raer)
library(GenomicRanges)
library(Biostrings)
library(Rsamtools)
library(S4Vectors)

# 1. Create a small BAM file using Rsamtools example data
bam_src <- system.file("extdata", "ex1.bam", package = "Rsamtools")
file.copy(bam_src, "bam_files.bam")

# 2. Create a matching FASTA file
# The ex1.bam file has references 'seq1' (1575 bp) and 'seq2' (1584 bp)
seq1_seq <- paste0(rep("A", 1575), collapse = "")
seq2_seq <- paste0(rep("C", 1584), collapse = "")
fasta_seqs <- DNAStringSet(c(seq1 = seq1_seq, seq2 = seq2_seq))
writeXStringSet(fasta_seqs, "fafn.fasta")

# 3. Create the GRanges object for editing sites
# The vignette specifies 1-base intervals, strand, and REF/ALT metadata columns
editing_sites <- GRanges(
    seqnames = "seq1",
    ranges = IRanges(start = c(10, 20, 30, 40, 50), width = 1),
    strand = "+"
)
editing_sites$REF <- Rle("A")
editing_sites$ALT <- Rle("G")

saveRDS(editing_sites, "chr_18_editing_sites.gr")