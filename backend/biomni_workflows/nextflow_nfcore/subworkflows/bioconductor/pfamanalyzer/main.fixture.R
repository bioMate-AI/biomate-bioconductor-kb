library(pfamAnalyzeR)

pfamResultFile <- system.file(
    "extdata/pfam_results.txt",
    package = "pfamAnalyzeR"
)

if (file.exists(pfamResultFile)) {
    file.copy(pfamResultFile, "pfam_results.txt", overwrite = TRUE)
} else {
    stop("Could not find pfam_results.txt in pfamAnalyzeR package")
}