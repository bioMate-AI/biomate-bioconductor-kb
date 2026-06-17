# Real user-style input for methimpute (separate-context methylation calling):
#   arabidopsis_sequence.fa.gz  - the genome reference FASTA the user aligned
#                                 against (one short contig here, gzipped FASTA).
#   arabidopsis_bsseeker.txt.gz - a BSSeeker2 cytosine-methylation report for that
#                                 reference. BSSeeker format read by
#                                 methimpute::importBSSeeker is an 8-column TSV:
#                                   V1 chromosome
#                                   V2 nucleotide  (C = + strand, G = - strand)
#                                   V3 position    (1-based, on a real cytosine)
#                                   V4 context     (CG / CHG / CHH)
#                                   V5 di/tri-nucleotide context string
#                                   V6 methylation level (0..1)
#                                   V7 methylated read count
#                                   V8 total read count
# The methylation positions/contexts are DERIVED from the actual cytosines in the
# FASTA (via methimpute::extractCytosinesFromFASTA), so the report and the
# reference are mutually consistent — exactly the contract inflateMethylome()
# needs (it overlaps the report against the FASTA-extracted cytosines). The read
# counts are the user's own synthetic measurements. No package demo data.
suppressPackageStartupMessages({
  library(methimpute)
  library(Biostrings)
})

set.seed(2024)

# --- Build a short reference contig with realistic plant-genome base content ---
# (Arabidopsis is AT-rich; ensure plenty of cytosines in all three contexts.)
contig_len <- 20000
bases <- sample(c("A", "T", "C", "G"), contig_len, replace = TRUE,
                prob = c(0.33, 0.33, 0.17, 0.17))
seq_str <- paste(bases, collapse = "")
dna <- DNAStringSet(seq_str)
names(dna) <- "Chr1"
writeXStringSet(dna, "arabidopsis_sequence.fa.gz", compress = TRUE)

# --- Extract the genuine cytosine positions/contexts from this FASTA ---
cyt <- extractCytosinesFromFASTA("arabidopsis_sequence.fa.gz",
                                 contexts = c("CG", "CHG", "CHH"))

# --- Build a BSSeeker report covering a realistic subset of those cytosines ---
# Sample ~60% of cytosines as "covered" (the rest are uncovered, which methimpute
# imputes). Methylation levels differ by context, as in real bisulfite data.
n_cyt <- length(cyt)
covered_idx <- sort(sample.int(n_cyt, size = floor(0.6 * n_cyt)))
cc <- cyt[covered_idx]

ctx <- as.character(cc$context)
chrom <- as.character(seqnames(cc))
pos <- start(cc)
strand_chr <- ifelse(as.character(strand(cc)) == "-", "G", "C")

# Context-dependent mean methylation: CG high, CHG medium, CHH low.
mean_meth <- c(CG = 0.7, CHG = 0.4, CHH = 0.08)[ctx]
total <- rpois(length(cc), lambda = 12) + 1L
methylated <- rbinom(length(cc), size = total, prob = mean_meth)
level <- round(methylated / total, 4)

# di/tri-nucleotide string column (BSSeeker col 5) — descriptive, not parsed.
tri <- ctx

bsseeker <- data.frame(
  V1 = chrom,
  V2 = strand_chr,
  V3 = pos,
  V4 = ctx,
  V5 = tri,
  V6 = level,
  V7 = methylated,
  V8 = total,
  stringsAsFactors = FALSE
)
# Order by position (BSSeeker output is coordinate-sorted).
bsseeker <- bsseeker[order(bsseeker$V3), ]

gz <- gzfile("arabidopsis_bsseeker.txt.gz", "w")
write.table(bsseeker, gz, sep = "\t", quote = FALSE,
            row.names = FALSE, col.names = FALSE)
close(gz)
