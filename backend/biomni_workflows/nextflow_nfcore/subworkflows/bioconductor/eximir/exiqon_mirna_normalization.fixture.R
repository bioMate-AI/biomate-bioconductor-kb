library(ExiMiR)

# Load the example datasets as shown in the vignette
data(galenv, package = "ExiMiR")
data(GSE20122, package = "ExiMiR")

# Locate the Exiqon directory or files within the package
pkg_dir <- system.file(package = "ExiMiR")
all_files <- list.files(pkg_dir, recursive = TRUE, full.names = TRUE)

# Find samplesinfo.txt which maps the TXT files
samplesinfo_path <- grep("Exiqon/samplesinfo\\.txt$", all_files, value = TRUE)
if (length(samplesinfo_path) == 0) {
    samplesinfo_path <- grep("samplesinfo\\.txt$", all_files, value = TRUE)
}

if (length(samplesinfo_path) > 0) {
    exiqon_dir <- dirname(samplesinfo_path[1])
    # Copy all files (TXT, GAL, samplesinfo.txt) from that directory to the current working directory
    exiqon_files <- list.files(exiqon_dir, full.names = TRUE)
    file.copy(exiqon_files, ".", overwrite = TRUE)
} else {
    # Fallback to synthetic files if not found in the installation
    samples_data <- data.frame(
        Array = c("Array1", "Array2"),
        Hy3 = c("sample1_Hy3.txt", "sample2_Hy3.txt"),
        Hy5 = c("sample1_Hy5.txt", "sample2_Hy5.txt")
    )
    write.table(samples_data, "samplesinfo.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    
    txt_content <- c(
        "Begin Header",
        "End Header",
        "Field\tGene ID\tSignal Mean\tBackground Mean",
        "1\tmiR-1\t1500\t100",
        "2\tmiR-2\t2500\t150"
    )
    for (f in c(samples_data$Hy3, samples_data$Hy5)) {
        writeLines(txt_content, f)
    }
    
    gal_content <- c(
        "ATF\t1.0",
        "1\t2",
        "Type=GenePix ArrayList V1.0",
        "Block\tColumn\tRow\tID\tName",
        "1\t1\t1\tmiR-1\tmiR-1",
        "1\t1\t2\tmiR-2\tmiR-2"
    )
    writeLines(gal_content, "annotation.gal")
}