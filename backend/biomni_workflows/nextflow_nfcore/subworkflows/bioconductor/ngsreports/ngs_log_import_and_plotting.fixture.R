library(ngsReports)

ext <- system.file("extdata", package = "ngsReports")

# 1. Sample1.trimmomaticPE.txt
trim_files <- list.files(ext, pattern = "trimmomatic", ignore.case = TRUE, recursive = TRUE, full.names = TRUE)
if (length(trim_files) > 0) {
    file.copy(trim_files[1], "Sample1.trimmomaticPE.txt")
} else {
    writeLines(c(
        "TrimmomaticPE: Started with arguments: -threads 4 input_fwd.fq input_rev.fq output_fwd_paired.fq output_fwd_unpaired.fq output_rev_paired.fq output_rev_unpaired.fq ILLUMINACLIP:TruSeq3-PE.fa:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36",
        "Multiple cores found: Using 4 threads",
        "Using PrefixPair: 'TACACTCTTTCCCTACACGACGCTCTTCCGATCT' and 'GTGACTGGAGTTCAGACGTGTGCTCTTCCGATCT'",
        "ILLUMINACLIP: Using 1 prefix pairs, 0 sequence tuples, 0 forward only tuples, 0 reverse only tuples",
        "Input Read Pairs: 10000 Both Surviving: