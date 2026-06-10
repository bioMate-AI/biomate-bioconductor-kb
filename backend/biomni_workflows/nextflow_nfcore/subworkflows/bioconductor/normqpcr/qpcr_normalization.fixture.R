library(NormqPCR)

path <- system.file("exData", package = "NormqPCR")
taqman.example <- file.path(path, "example.txt")

if (file.exists(taqman.example)) {
    file.copy(taqman.example, "example.txt", overwrite = TRUE)
} else {
    stop("example.txt not found in NormqPCR exData directory.")
}