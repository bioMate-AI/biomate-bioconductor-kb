library(Biostrings)
library(rtracklayer)

# Define chromosomes based on the vignette's Axt alignments
hg38_chrs <- c("chr1", "chr6", "chr7", "chr8", "chr10", "chr13", "chr2", "chr9")
danRer10_chrs <- c("chr1", "chr2", "chr6", "chr7", "chr9")

set.seed(123)

# Generate dummy sequences for hg38
hg38_seqs <- DNAStringSet(lapply(hg38_chrs, function(x) {
    paste0(sample(c("A", "C", "G", "T"), 5000, replace = TRUE), collapse = "")
}))
names(hg38_seqs) <- hg38_chrs
writeXStringSet(hg38_seqs, "hg38.fa")

# Generate dummy sequences for danRer10
danRer10_seqs <- DNAStringSet(lapply(danRer10_chrs, function(x) {
    paste0(sample(c("A", "C", "G", "T"), 5000, replace = TRUE), collapse = "")
}))
names(danRer10_seqs) <- danRer10_chrs
writeXStringSet(danRer10_seqs, "danRer10.fa")

# Generate a combined 2bit file for both genomes
# (The workflow lists single_sequences.2bit twice, likely expecting one per genome, 
# but since they are read from the same working directory, we combine the unique chromosomes)
all_chrs <- unique(c(hg38_chrs, danRer10_chrs))
all_seqs <- DNAStringSet(lapply(all_chrs, function(x) {
    paste0(sample(c("A", "C", "G", "T"), 5000, replace = TRUE), collapse = "")
}))
names(all_seqs) <- all_chrs
export.2bit(all_seqs, "single_sequences.2bit")