library(QSutils)

fw_src <- system.file("extdata", "ToyData_FWReads.fna", package="QSutils")
if (fw_src != "" && file.exists(fw_src)) {
    file.copy(fw_src, "ToyData_FWReads.fna", overwrite = TRUE)
} else {
    writeLines(c(">Hpl_1|100|10", "ACGTACGTACGT", ">Hpl_2|900|90", "ACGTACGTACGA"), "ToyData_FWReads.fna")
}

rv_src <- system.file("extdata", "ToyData_RVReads.fna", package="QSutils")
if (rv_src != "" && file.exists(rv_src)) {
    file.copy(rv_src, "ToyData_RVReads.fna", overwrite = TRUE)
} else {
    writeLines(c(">Hpl_1|100|10", "ACGTACGTACGT", ">Hpl_2|900|90", "ACGTACGTACGA"), "ToyData_RVReads.fna")
}