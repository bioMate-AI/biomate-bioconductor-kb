library(MethTargetedNGS)

healthy_src <- system.file("extdata", "Healthy.fasta", package = "MethTargetedNGS")
if (file.exists(healthy_src)) {
    file.copy(healthy_src, "Healthy.fasta", overwrite = TRUE)
} else {
    writeLines(c(">read1", "CGTACG"), "Healthy.fasta")
}

tumor_src <- system.file("extdata", "Tumor.fasta", package = "MethTargetedNGS")
if (file.exists(tumor_src)) {
    file.copy(tumor_src, "Tumor.fasta", overwrite = TRUE)
} else {
    writeLines(c(">read1", "CGTACG"), "Tumor.fasta")
}

reference_src <- system.file("extdata", "Reference.fasta", package = "MethTargetedNGS")
if (file.exists(reference_src)) {
    file.copy(reference_src, "Reference.fasta", overwrite = TRUE)
} else {
    writeLines(c(">ref", "CGTACG"), "Reference.fasta")
}