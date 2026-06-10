library(DEGseq)

kidney_src <- system.file("extdata", "kidneyChr21.bed.txt", package="DEGseq")
if (file.exists(kidney_src)) {
    file.copy(kidney_src, "kidneyChr21.bed.txt", overwrite = TRUE)
} else {
    # Fallback synthetic BED file if not found
    writeLines(c("chr21\t100\t150\tread1\t255\t+"), "kidneyChr21.bed.txt")
}

refFlat_src <- system.file("extdata", "refFlatChr21.txt", package="DEGseq")
if (file.exists(refFlat_src)) {
    file.copy(refFlat_src, "refFlatChr21.txt", overwrite = TRUE)
} else {
    # Fallback synthetic refFlat file if not found
    writeLines(c("geneA\tNM_001\tchr21\t+\t100\t200\t100\t200\t1\t100,\t200,"), "refFlatChr21.txt")
}