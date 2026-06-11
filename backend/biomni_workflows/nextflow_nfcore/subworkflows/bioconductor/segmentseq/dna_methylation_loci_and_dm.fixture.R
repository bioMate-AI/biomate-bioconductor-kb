library(segmentSeq)

# Define the expected input files
files <- c(
  "short_18B_C24_C24_trim.fastq_CG_methCalls.gz",
  "short_Sample_17A_trimmed.fastq_CG_methCalls.gz",
  "short_13_C24_col_trim.fastq_CG_methCalls.gz",
  "short_Sample_28_trimmed.fastq_CG_methCalls.gz"
)

# Create synthetic methylation call data
# readMeths typically expects tab-delimited files with columns for:
# chromosome, position, strand, methylated counts, unmethylated counts
meth_data <- data.frame(
  chr = c("Chr1", "Chr1", "Chr1", "Chr2", "Chr2"),
  pos = c(100, 200, 300, 150, 250),
  strand = c("+", "-", "+", "+", "-"),
  meth = c(10, 15, 5, 20, 0),
  unmeth = c(2, 1, 10, 0, 20)
)

# Write the synthetic data to gzipped files
for (f in files) {
  gz <- gzfile(f, "w")
  write.table(meth_data, file = gz, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
  close(gz)
}