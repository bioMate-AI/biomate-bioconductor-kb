library(segmentSeq)

# Construct synthetic YAMA methylation calls data
# YAMA typically outputs columns for chromosome, position, strand, 
# and counts for methylated (mc), hydroxymethylated (h), and unmethylated (c) cytosines.
meth_data <- data.frame(
  chr = c("Chr1", "Chr1", "Chr1", "Chr2", "Chr2"),
  pos = c(100, 150, 200, 100, 150),
  strand = c("+", "-", "+", "+", "-"),
  mc = c(10, 5, 0, 8, 2),
  h = c(0, 0, 0, 0, 0),
  c = c(0, 5, 10, 2, 8)
)

# Declared input files
files <- c(
  "short_18B_C24_C24_trim.fastq_CG_methCalls.gz",
  "short_Sample_17A_trimmed.fastq_CG_methCalls.gz",
  "short_13_C24_col_trim.fastq_CG_methCalls.gz",
  "short_Sample_28_trimmed.fastq_CG_methCalls.gz"
)

# Write the synthetic data to the expected gzipped files
for (f in files) {
  gz_conn <- gzfile(f, "w")
  write.table(meth_data, gz_conn, sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)
  close(gz_conn)
}