library(ngsReports)

ext_dir <- system.file("extdata", package = "ngsReports")

# 1. Trimmomatic PE log
if (length(f <- list.files(ext_dir, pattern = "trimmomatic.*\\.log$", ignore.case = TRUE, full.names = TRUE)) > 0) {
  file.copy(f[1], "trimmomatic_log.txt", overwrite = TRUE)
} else {
  writeLines(c(
    "TrimmomaticPE: Started with arguments:",
    " -threads 8 input_R1.fastq input_R2.fastq output_R1.fastq output_R1_unpaired.fastq output_R2.fastq output_R2_unpaired.fastq ILLUMINACLIP:TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36",
    "Multiple cores found: Using 8 threads",
    "Using PrefixPair: 'TACACTCTTTCCCTACACGACGCTCTTCCGATCT' and 'GTGACTGGAGTTCAGACGTGTGCTCTTCCGATCT'",
    "ILLUMINACLIP: Using 1 prefix pairs, 0 forward/reverse sequences, 0 forward only sequences, 0 reverse only sequences",
    "Input Read Pairs: 100000 Both Surviving: 9