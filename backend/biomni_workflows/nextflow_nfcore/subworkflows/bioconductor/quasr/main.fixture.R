suppressPackageStartupMessages({
    library(QuasR)
})

extdata_dir <- system.file("extdata", package = "QuasR")

# 1. samples_chip_single.txt
sample_files <- list.files(extdata_dir, pattern = "samples_chip_single\\.txt$", recursive = TRUE, full.names = TRUE)
if (length(sample_files) > 0) {
    samples <- read.table(sample_files[1], header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    # Rewrite relative paths to absolute paths so qAlign can find the FASTQ files
    if ("FileName" %in% colnames(samples)) {
        samples$FileName <- file.path(dirname(sample_files[1]), basename(samples$FileName))
    }
    write.table(samples, "samples_chip_single.txt", sep = "\t", row.names = FALSE, quote = FALSE)
} else {
    samples <- data.frame(FileName = "dummy.fq", SampleName = "Sample1")
    write.table(samples, "samples_chip_single.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

# 2. hg19sub.fa
fa_files <- list.files(extdata_dir, pattern = "hg19sub\\.fa$", recursive = TRUE, full.names = TRUE)
if (length(fa_files) > 0) {
    file.copy(fa_files[1], "hg19sub.fa", overwrite = TRUE)
} else {
    writeLines(c(">chr1", "ACGTACGTACGT"), "hg19sub.fa")
}

# 3. auxiliaries.txt
aux_files <- list.files(extdata_dir, pattern = "auxiliaries\\.txt$", recursive = TRUE, full.names = TRUE)
if (length(aux_files) > 0) {
    aux <- read.table(aux_files[1], header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    # Rewrite relative paths to absolute paths
    if ("FileName" %in% colnames(aux)) {
        aux$FileName <- file.path(dirname(aux_files[1]), basename(aux$FileName))
    }
    write.table(aux, "auxiliaries.txt", sep = "\t", row.names = FALSE, quote = FALSE)
} else {
    aux <- data.frame(FileName = character(0), AuxName = character(0))
    write.table(aux, "auxiliaries.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

# 4. hg19sub_annotation.gtf
gtf_files <- list.files(extdata_dir, pattern = "hg19sub_annotation\\.gtf$", recursive = TRUE, full.names = TRUE)
if (length(gtf_files) > 0) {
    file.copy(gtf_files[1], "hg19sub_annotation.gtf", overwrite = TRUE)
} else {
    writeLines(c('chr1\tQuasR\texon\t1\t10\t.\t+\t.\tgene_id "g1"; transcript_id "t1";'), "hg19sub_annotation.gtf")
}