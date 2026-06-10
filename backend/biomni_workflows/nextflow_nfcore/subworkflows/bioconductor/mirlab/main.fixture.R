library(miRLAB)

# Locate and copy the dataset file
dataset_src <- system.file("extdata", "ToyEMT.csv", package="miRLAB")
if (!file.exists(dataset_src)) {
    dataset_src <- list.files(system.file("extdata", package="miRLAB"), pattern="EMT.*\\.csv$", full.names=TRUE)[1]
}

if (!is.na(dataset_src) && file.exists(dataset_src)) {
    file.copy(dataset_src, "dataset.csv", overwrite = TRUE)
} else {
    # Fallback: create synthetic dataset
    df <- data.frame(
        miR_1 = rnorm(10),
        miR_2 = rnorm(10),
        miR_3 = rnorm(10),
        mRNA_1 = rnorm(10),
        mRNA_2 = rnorm(10),
        mRNA_3 = rnorm(10)
    )
    write.csv(df, "dataset.csv", row.names = FALSE)
}

# Locate and copy the ground truth file
gt_src <- system.file("extdata", "Toygroundtruth.csv", package="miRLAB")
if (!file.exists(gt_src)) {
    gt_src <- list.files(system.file("extdata", package="miRLAB"), pattern="groundtruth.*\\.csv$", full.names=TRUE)[1]
}

if (!is.na(gt_src) && file.exists(gt_src)) {
    file.copy(gt_src, "groundtruth.csv", overwrite = TRUE)
} else {
    # Fallback: create synthetic ground truth
    gt <- data.frame(
        miRNA = c("miR_1", "miR_2"),
        mRNA = c("mRNA_1", "mRNA_2")
    )
    write.csv(gt, "groundtruth.csv", row.names = FALSE)
}