library(QSutils)

fw_src <- system.file("extdata", "ToyData_FWReads.fna", package="QSutils")
if (fw_src == "" || !file.exists(fw_src)) {
    fw_src <- list.files(system.file("extdata", package="QSutils"), pattern="ToyData_FWReads\\.fna$", recursive=TRUE, full.names=TRUE)[1]
}

if (!is.na(fw_src) && file.exists(fw_src)) {
    file.copy(fw_src, "ToyData_FWReads.fna", overwrite=TRUE)
} else {
    writeLines(c(">Hpl_0_0001|464|46.4", "CACCCTGTGACCAGTGTGTGCGAGTTTGGTGCCCCGTTGGCATTGACTAT"), "ToyData_FWReads.fna")
}

rv_src <- system.file("extdata", "ToyData_RVReads.fna", package="QSutils")
if (rv_src == "" || !file.exists(rv_src)) {
    rv_src <- list.files(system.file("extdata", package="QSutils"), pattern="ToyData_RVReads\\.fna$", recursive=TRUE, full.names=TRUE)[1]
}

if (!is.na(rv_src) && file.exists(rv_src)) {
    file.copy(rv_src, "ToyData_RVReads.fna", overwrite=TRUE)
} else {
    writeLines(c(">Hpl_0_0001|464|46.4", "CACCCTGTGACCAGTGTGTGCGAGTTTGGTGCCCCGTTGGCATTGACTAT"), "ToyData_RVReads.fna")
}