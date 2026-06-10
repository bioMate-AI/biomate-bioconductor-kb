library(QuasR)

extdata_dir <- system.file("extdata", package = "QuasR")

file.copy(file.path(extdata_dir, "hg19sub.fa"), "hg19sub.fa", overwrite = TRUE)
file.copy(file.path(extdata_dir, "hg19sub_annotation.gtf"), "hg19sub_annotation.gtf", overwrite = TRUE)

sample_file_path <- file.path(extdata_dir, "samples_rna_paired.txt")
if (file.exists(sample_file_path)) {
    samples <- read.table(sample_file_path, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    
    if ("FileName1" %in% colnames(samples)) {
        samples$FileName1 <- file.path(extdata_dir, basename(samples$FileName1))
    }
    if ("FileName2" %in% colnames(samples)) {
        samples$FileName2 <- file.path(extdata_dir, basename(samples$FileName2))
    }
    
    write.table(samples, "samples_rna_paired.txt", sep = "\t", row.names = FALSE, quote = FALSE)
} else {
    samples <- data.frame(
        FileName1 = file.path(extdata_dir, "rna_1_1.fq.bz2"),
        FileName2 = file.path(extdata_dir, "rna_1_2.fq.bz2"),
        SampleName = "Sample1",
        stringsAsFactors = FALSE
    )
    write.table(samples, "samples_rna_paired.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}