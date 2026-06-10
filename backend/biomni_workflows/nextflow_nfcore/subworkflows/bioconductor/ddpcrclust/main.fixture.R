library(ddPCRclust)

# Locate example files shipped with the package
exampleFiles <- list.files(system.file('extdata', package='ddPCRclust'), full.names = TRUE, pattern = "\\.csv$")

# Separate template file from amplitude files
template_file_src <- exampleFiles[grep("template", tolower(basename(exampleFiles)))][1]
amp_files_src <- exampleFiles[!grepl("template", tolower(basename(exampleFiles)))]

# 1. Write amplitude file
if (length(amp_files_src) > 0) {
    # Copy the first available amplitude file
    file.copy(amp_files_src[1], basename(amp_files_src[1]), overwrite = TRUE)
    # Also provide a generic name to ensure it's found
    file.copy(amp_files_src[1], "amplitude.csv", overwrite = TRUE)
} else {
    # Fallback: Create synthetic amplitude data based on vignette
    amp_data <- data.frame(
        "Ch1 Amplitude" = c(2360.098, 2396.3916, 2445.838, 2451.63867, 2492.55884, 2519.6355),
        "Ch2 Amplitude" = c(6119.26953, 1415.31665, 6740.79639, 1381.74683, 1478.19617, 7082.25049),
        check.names = FALSE
    )
    write.csv(amp_data, "B01_amplitude.csv", row.names = FALSE, quote = FALSE)
    write.csv(amp_data, "amplitude.csv", row.names = FALSE, quote = FALSE)
}

# 2. Write template file
if (!is.na(template_file_src) && file.exists(template_file_src)) {
    file.copy(template_file_src, "template.csv", overwrite = TRUE)
} else {
    # Fallback: Create synthetic template data based on vignette
    template_data <- data.frame(
        "Well" = c("B01", "G01", "F02", "D03", "A04", "G07", "G08", "E09"),
        "Sample type" = c("Blood", "FFPE", "Blood", "FFPE", "FFPE", "Cell line", "Cell line", "FFPE"),
        "No of markers" = c(4, 4, 3, 3, 4, 3, 3, 2),
        "Marker 1" = c("a", "a", "a", "a", "a", "a", "a", ""),
        "Marker 2" = c("b", "b", "", "", "b", "", "", ""),
        "Marker 3" = c("c", "c", "c", "c", "c", "c", "c", "c"),
        "Marker 4" = c("d", "d", "d", "d", "d", "d", "d", "d"),
        check.names = FALSE
    )
    write.csv(template_data, "template.csv", row.names = FALSE, quote = FALSE)
}