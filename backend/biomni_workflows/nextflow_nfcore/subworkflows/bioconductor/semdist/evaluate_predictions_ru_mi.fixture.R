library(SemDist)

truefile <- system.file("extdata", "MFO_LABELS_TEST.txt", package="SemDist")
if (file.exists(truefile)) {
    file.copy(truefile, "MFO_LABELS_TEST.txt", overwrite = TRUE)
} else {
    # Fallback synthetic data if the package file is missing
    cat("P12345\tGO:0003674\nP12345\tGO:0005575\n", file="MFO_LABELS_TEST.txt")
}

predfile <- system.file("extdata", "MFO_PREDS_TEST.txt", package="SemDist")
if (file.exists(predfile)) {
    file.copy(predfile, "MFO_PREDS_TEST.txt", overwrite = TRUE)
} else {
    # Fallback synthetic data if the package file is missing
    cat("P12345\tGO:0003674\t0.9\nP12345\tGO:0005575\t0.8\n", file="MFO_PREDS_TEST.txt")
}