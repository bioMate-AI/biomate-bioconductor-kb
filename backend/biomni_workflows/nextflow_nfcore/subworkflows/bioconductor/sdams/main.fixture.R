library("SDAMS")

# Locate the shipped example files
directory1 <- system.file("extdata", package = "SDAMS", mustWork = TRUE)
path1 <- file.path(directory1, "ProstateFeature.csv")
directory2 <- system.file("extdata", package = "SDAMS", mustWork = TRUE)
path2 <- file.path(directory2, "ProstateGroup.csv")

# Copy them to the expected input filenames in the working directory
if (file.exists(path1)) {
    file.copy(path1, "feature.csv", overwrite = TRUE)
} else {
    # Fallback if the file is missing but data is available
    data("exampleSumExp", package = "SDAMS")
    write.csv(assay(exampleSumExp), "feature.csv", quote = FALSE)
}

if (file.exists(path2)) {
    file.copy(path2, "group.csv", overwrite = TRUE)
} else {
    # Fallback if the file is missing but data is available
    data("exampleSumExp", package = "SDAMS")
    write.csv(as.data.frame(colData(exampleSumExp)), "group.csv", quote = FALSE)
}