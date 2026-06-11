suppressPackageStartupMessages({
    library(isobar)
})

# Reproduce the vignette's data preparation
data(ibspiked_set1)
ceru.human <- protein.g(proteinGroup(ibspiked_set1), "CERU_HUMAN")
ceru.rat <- protein.g(proteinGroup(ibspiked_set1), "CERU_RAT")
ceru.mouse <- protein.g(proteinGroup(ibspiked_set1), "CERU_MOUSE")
ceru.proteins <- c(ceru.human, ceru.rat, ceru.mouse)

# Attempt to find shipped .mgf and .id.csv files in the isobar package
mgf_files <- list.files(system.file(package="isobar"), pattern="\\.mgf$", full.names=TRUE, recursive=TRUE)
id_files <- list.files(system.file(package="isobar"), pattern="\\.id\\.csv$", full.names=TRUE, recursive=TRUE)

# Write peaklist.mgf
if (length(mgf_files) > 0) {
    file.copy(mgf_files[1], "peaklist.mgf", overwrite=TRUE)
} else {
    # Create a minimal valid MGF file if none is shipped
    mgf_content <- c(
        "BEGIN IONS",
        "TITLE=Spectrum_1",
        "PEPMASS=400.0",
        "CHARGE=2+",
        "114.1112 1000",
        "115.1083 1000",
        "116.1116 1000",
        "117.1150 1000",
        "END IONS"
    )
    writeLines(mgf_content, "peaklist.mgf")
}

# Write identifications.id.csv
if (length(id_files) > 0) {
    file.copy(id_files[1], "identifications.id.csv", overwrite=TRUE)
} else {
    # Create a valid identifications file using the spiked dataset
    # isobar often uses tab-separated format for .id.csv files
    df <- as.data.frame(ibspiked_set1)
    write.table(df, "identifications.id.csv", sep="\t", row.names=FALSE, quote=FALSE)
}

# Guarantee the declared input files exist
stopifnot(file.exists("identifications.id.csv"))
stopifnot(file.exists("peaklist.mgf"))