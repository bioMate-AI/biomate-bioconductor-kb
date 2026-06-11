library(DEGseq)

kidney_file <- system.file("extdata", "kidneyChr21.bed.txt", package="DEGseq")
liver_file <- system.file("extdata", "liverChr21.bed.txt", package="DEGseq")
refflat_file <- system.file("extdata", "refFlatChr21.txt", package="DEGseq")

if (file.exists(kidney_file)) {
    file.copy(kidney_file, "sample1.bed", overwrite = TRUE)
} else {
    writeLines(c("chr21\t100\t200\tread1\t0\t+", "chr21\t150\t250\tread2\t0\t-"), "sample1.bed")
}

if (file.exists(liver_file)) {
    file.copy(liver_file, "sample2.bed", overwrite = TRUE)
} else {
    writeLines(c("chr21\t100\t200\tread3\t0\t+", "chr21\t150\t250\tread4\t0\t-"), "sample2.bed")
}

if (file.exists(refflat_file)) {
    file.copy(refflat_file, "refFlat.txt", overwrite = TRUE)
} else {
    writeLines(c("Gene1\tNM_001\tchr21\t+\t100\t250\t100\t250\t1\t100,\t250,"), "refFlat.txt")
}