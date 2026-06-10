library(ASICS)
library(ASICSdata)

# 1. Create design_file.txt
design_src <- system.file("extdata", "design_diabete_example.txt", package = "ASICSdata")
if (file.exists(design_src)) {
    file.copy(design_src, "design_file.txt", overwrite = TRUE)
} else {
    # Fallback if the file is not found
    design <- data.frame(
        sample = c("ADG10003u_007", "ADG10003u_008"),
        condition = c("Control", "diabetes mellitus")
    )
    write.table(design, "design_file.txt", row.names = FALSE, quote = FALSE, sep = "\t")
}

# 2. Create spectra_file.txt
spectra_src <- system.file("extdata", "spectra_diabetes_example.txt", package = "ASICSdata")
if (file.exists(spectra_src)) {
    file.copy(spectra_src, "spectra_file.txt", overwrite = TRUE)
} else {
    # Fallback if the file is not found
    spectra <- data.frame(
        ADG10003u_007 = c(0.1, 0.2),
        ADG10003u_008 = c(0.15, 0.25)
    )
    rownames(spectra) <- c("0.00", "0.01")
    write.table(spectra, "spectra_file.txt", row.names = TRUE, quote = FALSE, sep = "\t")
}

# 3. Create raw_spectra_directory
raw_src <- system.file("extdata", "Human_diabetes_example", package = "ASICSdata")
dir.create("raw_spectra_directory", showWarnings = FALSE)
if (file.exists(raw_src)) {
    file.copy(list.files(raw_src, full.names = TRUE), "raw_spectra_directory", recursive = TRUE, overwrite = TRUE)
}