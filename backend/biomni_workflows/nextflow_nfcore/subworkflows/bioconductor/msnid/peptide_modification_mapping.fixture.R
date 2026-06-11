library(MSnID)

mzid_src <- system.file("extdata", "phospho.mzid.gz", package="MSnID")
if (file.exists(mzid_src)) {
    file.copy(mzid_src, "phospho.mzid.gz", overwrite = TRUE)
} else {
    stop("phospho.mzid.gz not found in MSnID extdata")
}

fasta_src <- system.file("extdata", "for_phospho.fasta.gz", package="MSnID")
if (file.exists(fasta_src)) {
    file.copy(fasta_src, "for_phospho.fasta.gz", overwrite = TRUE)
} else {
    stop("for_phospho.fasta.gz not found in MSnID extdata")
}