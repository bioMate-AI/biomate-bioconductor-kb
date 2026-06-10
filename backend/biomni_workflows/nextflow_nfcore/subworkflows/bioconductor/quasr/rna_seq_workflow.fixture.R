suppressPackageStartupMessages({
    library(QuasR)
})

extdata_dir <- system.file("extdata", package = "QuasR")

# 1. Prepare samples_rna_paired.txt
# Read the template from extdata and update the fastq paths to be absolute
# so that the workflow can find them without needing to copy the fastq files.
sample_file_in <- file.path(extdata_dir, "samples_rna_paired.txt")
if (file.exists(sample_file_in)) {
    samples <- read.table(sample_file_in, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    samples$FileName1 <- file.path(extdata_dir, basename(samples$FileName1))
    samples$FileName2 <- file.path(extdata_dir, basename(samples$FileName2))
    write.table(samples, "samples_rna_paired.txt", sep = "\t", row.names = FALSE, quote = FALSE)
} else {
    # Fallback synthetic creation if missing
    samples <- data.frame(
        FileName1 = file.path(extdata_dir, "rna_1_1.fq.bz2"),
        FileName2 = file.path(extdata_dir, "rna_1_2.fq.bz2"),
        SampleName = "Sample1",
        stringsAsFactors = FALSE
    )
    write.table(samples, "samples_rna_paired.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

# 2. Prepare hg19sub.fa
fa_in <- file.path(extdata_dir, "hg19sub.fa")
if (file.exists(fa_in)) {
    file.copy(fa_in, "hg19sub.fa", overwrite = TRUE)
} else {
    # Fallback synthetic creation
    writeLines(c(">chr1", "ACGTACGTACGT"), "hg19sub.fa")
}

# 3. Prepare hg19sub_annotation.gtf
gtf_in <- file.path(extdata_dir, "hg19sub_annotation.gtf")
if (file.exists(gtf_in)) {
    file.copy(gtf_in, "hg19sub_annotation.gtf", overwrite = TRUE)
} else {
    # Fallback synthetic creation
    writeLines(c('chr1\tunknown\texon\t1\t10\t.\t+\t.\tgene_id "gene1"; transcript_id "tx1";'), "hg19sub_annotation.gtf")
}