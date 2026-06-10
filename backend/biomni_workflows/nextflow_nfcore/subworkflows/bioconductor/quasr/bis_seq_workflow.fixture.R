library(QuasR)
library(Rsamtools)

extdata_dir <- system.file("extdata", package = "QuasR")

# 1. Prepare reference genome fasta file
fa_path <- file.path(extdata_dir, "hg19sub.fa")
if (file.exists(fa_path)) {
    file.copy(fa_path, "hg19sub.fa", overwrite = TRUE)
} else {
    # Fallback synthetic fasta if not found
    writeLines(c(">chr1", "ACGTACGTACGT"), "hg19sub.fa")
}
# Ensure the fasta file is indexed for scanFaIndex()
indexFa("hg19sub.fa")

# 2. Prepare gene annotation file
gtf_path <- file.path(extdata_dir, "hg19sub_annotation.gtf")
if (file.exists(gtf_path)) {
    file.copy(gtf_path, "hg19sub_annotation.gtf", overwrite = TRUE)
} else {
    # Fallback synthetic GTF if not found
    writeLines(c('chr1\tQuasR\texon\t1\t10\t.\t+\t.\tgene_id "g1"; transcript_id "t1";'), "hg19sub_annotation.gtf")
}

# 3. Prepare sample file listing bisulfite fasta/fastq files
sample_file <- file.path(extdata_dir, "samples_bis_single.txt")
if (file.exists(sample_file)) {
    df <- read.delim(sample_file, stringsAsFactors = FALSE)
    # Fix relative paths to absolute paths so they can be resolved from the working directory
    for (i in seq_len(nrow(df))) {
        if (!file.exists(df$FileName[i])) {
            cand <- file.path(extdata_dir, basename(df$FileName[i]))
            if (file.exists(cand)) {
                df$FileName[i] <- cand
            }
        }
    }
    write.table(df, "samples_bis_single.txt", sep = "\t", row.names = FALSE, quote = FALSE)
} else {
    # Fallback synthetic sample file if not found
    fq_files <- list.files(extdata_dir, pattern = "bis.*\\.fq", full.names = TRUE)
    if (length(fq_files) == 0) {
        dummy_fq <- "dummy_bis.fq"
        writeLines(c("@seq1", "CGTACG", "+", "IIIIII"), dummy_fq)
        fq_files <- dummy_fq
    }
    df <- data.frame(FileName = fq_files, SampleName = paste0("Sample", seq_along(fq_files)))
    write.table(df, "samples_bis_single.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}