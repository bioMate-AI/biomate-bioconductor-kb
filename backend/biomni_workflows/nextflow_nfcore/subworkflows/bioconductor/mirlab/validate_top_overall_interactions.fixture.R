library(miRLAB)

dataset_src <- system.file("extdata", "ToyEMT.csv", package="miRLAB")
if (dataset_src == "") {
    dataset_src <- system.file("extdata", "EMT35.csv", package="miRLAB")
}

if (dataset_src != "" && file.exists(dataset_src)) {
    file.copy(dataset_src, "dataset.csv", overwrite = TRUE)
} else {
    dataset_df <- data.frame(
        miR_200a = rnorm(20),
        miR_200b = rnorm(20),
        miR_200c = rnorm(20),
        ZEB1 = rnorm(20),
        ZEB2 = rnorm(20),
        CDH1 = rnorm(20),
        VIM = rnorm(20)
    )
    write.csv(dataset_df, "dataset.csv", row.names = FALSE, quote = FALSE)
}

gt_src <- system.file("extdata", "Toygroundtruth.csv", package="miRLAB")
if (gt_src != "" && file.exists(gt_src)) {
    file.copy(gt_src, "groundtruth.csv", overwrite = TRUE)
} else {
    gt_df <- data.frame(
        miRNA = c("miR_200a", "miR_200b", "miR_200c"),
        mRNA = c("ZEB1", "ZEB2", "ZEB1")
    )
    write.csv(gt_df, "groundtruth.csv", row.names = FALSE, quote = FALSE)
}