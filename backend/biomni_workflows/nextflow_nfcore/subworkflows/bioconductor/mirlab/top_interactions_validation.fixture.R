library(miRLAB)

toy_emt_path <- system.file("extdata", "ToyEMT.csv", package="miRLAB")
if (file.exists(toy_emt_path)) {
    file.copy(toy_emt_path, "ToyEMT.csv", overwrite = TRUE)
} else {
    stop("ToyEMT.csv not found in miRLAB extdata")
}

toy_gt_path <- system.file("extdata", "Toygroundtruth.csv", package="miRLAB")
if (file.exists(toy_gt_path)) {
    file.copy(toy_gt_path, "Toygroundtruth.csv", overwrite = TRUE)
} else {
    stop("Toygroundtruth.csv not found in miRLAB extdata")
}