library(ASICS)
library(ASICSdata)

spectra_src <- system.file("extdata", "spectra_diabetes_example.txt", package = "ASICSdata")
if (file.exists(spectra_src)) {
    file.copy(spectra_src, "spectra_file.txt", overwrite = TRUE)
} else {
    spectra_data <- data.frame(
        ADG10003u_007 = c(0.1, 0.2, 0.3),
        ADG10003u_008 = c(0.15, 0.25, 0.35),
        check.names = FALSE
    )
    rownames(spectra_data) <- c("0.001", "0.002", "0.003")
    write.table(spectra_data, "spectra_file.txt", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
}

design_src <- system.file("extdata", "design_diabete_example.txt", package = "ASICSdata")
if (file.exists(design_src)) {
    file.copy(design_src, "design_file.txt", overwrite = TRUE)
} else {
    design_data <- data.frame(
        sample = c("ADG10003u_007", "ADG10003u_008"),
        condition = c("Control", "diabetes mellitus")
    )
    write.table(design_data, "design_file.txt", sep = "\t", quote = FALSE, row.names = FALSE)
}