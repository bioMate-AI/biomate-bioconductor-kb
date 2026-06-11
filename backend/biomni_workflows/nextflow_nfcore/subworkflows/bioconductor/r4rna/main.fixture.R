library(R4RNA)

transat_file <- system.file("extdata", "helix.txt", package = "R4RNA")
if (file.exists(transat_file)) {
    file.copy(transat_file, "predicted_structure.txt", overwrite = TRUE)
} else {
    stop("helix.txt not found in R4RNA package")
}

known_file <- system.file("extdata", "vienna.txt", package = "R4RNA")
if (file.exists(known_file)) {
    file.copy(known_file, "known_structure.dbn", overwrite = TRUE)
} else {
    stop("vienna.txt not found in R4RNA package")
}