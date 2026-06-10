library(DEGseq)

kidney_bed <- system.file("extdata", "kidneyChr21.bed.txt", package="DEGseq")
refFlat_txt <- system.file("extdata", "refFlatChr21.txt", package="DEGseq")

if (file.exists(kidney_bed)) {
    file.copy(kidney_bed, "sample.bed", overwrite = TRUE)
} else {
    bed_data <- data.frame(
        chrom = c("chr21", "chr21", "chr21"),
        chromStart = c(9719768, 9721892, 9722000),
        chromEnd = c(9719793, 9721917, 9722025),
        name = c("U0", "U1", "U2"),
        score = c(0, 0, 0),
        strand = c("+", "-", "+")
    )
    write.table(bed_data, "sample.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
}

if (file.exists(refFlat_txt)) {
    file.copy(refFlat_txt, "refFlat.txt", overwrite = TRUE)
} else {
    refFlat_data <- data.frame(
        geneName = c("SAMSN1", "SAMSN1"),
        name = c("NM_022136", "NM_001000000"),
        chrom = c("chr21", "chr21"),
        strand = c("+", "+"),
        txStart = c(9719768, 9719768),
        txEnd = c(9721917, 9721917),
        cdsStart = c(9719768, 9719768),
        cdsEnd = c(9721917, 9721917),
        exonCount = c(2, 2),
        exonStarts = c("9719768,9721892,", "9719768,9721892,"),
        exonEnds = c("9719793,9721917,", "9719793,9721917,")
    )
    write.table(refFlat_data, "refFlat.txt", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
}