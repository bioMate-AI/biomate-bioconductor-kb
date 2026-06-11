library(specL)

blib_filtered_src <- system.file("extdata", "peptideStd.sqlite", package = "specL")
blib_redundant_src <- system.file("extdata", "peptideStd_redundant.sqlite", package = "specL")
fasta_src <- system.file("extdata", "SP201602-specL.fasta.gz", package = "specL")

if (file.exists(blib_filtered_src)) {
    file.copy(blib_filtered_src, "BLIB_FILTERED_FILE.sqlite", overwrite = TRUE)
} else {
    stop("Could not find peptideStd.sqlite in specL")
}

if (file.exists(blib_redundant_src)) {
    file.copy(blib_redundant_src, "BLIB_REDUNDANT_FILE.sqlite", overwrite = TRUE)
} else {
    stop("Could not find peptideStd_redundant.sqlite in specL")
}

if (file.exists(fasta_src)) {
    file.copy(fasta_src, "FASTA_FILE.fasta.gz", overwrite = TRUE)
} else {
    stop("Could not find SP201602-specL.fasta.gz in specL")
}