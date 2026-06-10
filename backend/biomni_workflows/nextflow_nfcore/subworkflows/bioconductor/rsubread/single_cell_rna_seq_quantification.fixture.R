library(Rsubread)

# Generate synthetic hg38_chr1.fa.gz (Reference genome FASTA file)
fasta_con <- gzfile("hg38_chr1.fa.gz", "w")
set.seed(123)
chr1_seq <- paste(sample(c("A", "C", "G", "T"), 10000, replace = TRUE), collapse = "")
writeLines(c(">chr1", chr1_seq), fasta_con)
close(fasta_con)

# Generate synthetic reads_R1.fastq.gz (Barcode and UMI read file, typically 28bp for 10x Genomics)
n_reads <- 100
r1_seqs <- replicate(n_reads, paste(sample(c("A", "C", "G", "T"), 28, replace = TRUE), collapse = ""))
r1_quals <- replicate(n_reads, paste(rep("I", 28), collapse = ""))
r1_lines <- c(rbind(paste0("@read", 1:n_reads), r1_seqs, "+", r1_quals))

r1_con <- gzfile("reads_R1.fastq.gz", "w")
writeLines(r1_lines, r1_con)
close(r1_con)

# Generate synthetic reads_R2.fastq.gz (RNA sequence read file, typically 90bp)
r2_seqs <- replicate(n_reads, paste(sample(c("A", "C", "G", "T"), 90, replace = TRUE), collapse = ""))
r2_quals <- replicate(n_reads, paste(rep("I", 90), collapse = ""))
r2_lines <- c(rbind(paste0("@read", 1:n_reads), r2_seqs, "+", r2_quals))

r2_con <- gzfile("reads_R2.fastq.gz", "w")
writeLines(r2_lines, r2_con)
close(r2_con)