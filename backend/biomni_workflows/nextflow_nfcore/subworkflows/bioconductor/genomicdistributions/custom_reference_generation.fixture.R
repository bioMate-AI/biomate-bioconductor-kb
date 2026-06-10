library(Biostrings)
library(rtracklayer)
library(GenomicRanges)

# Generate synthetic genome.fa.gz
dna <- DNAStringSet(c(
  chr1 = paste0(rep("ACGT", 250), collapse=""), 
  chr2 = paste0(rep("TGCA", 250), collapse="")
))
writeXStringSet(dna, "genome.fa.gz", compress = TRUE)

# Generate synthetic annotation.gtf.gz
gr <- GRanges(
  seqnames = c("chr1", "chr2"),
  ranges = IRanges(start = c(100, 200), end = c(500, 600)),
  strand = c("+", "-"),
  type = "gene",
  gene_id = c("gene1", "gene2"),
  transcript_id = c("tx1", "tx2")
)
export(gr, "annotation.gtf.gz", format = "gtf", compress = TRUE)