library(MetaPhOR)

src_file <- system.file("extdata", "BRCA_DEGS.csv", package = "MetaPhOR")

if (file.exists(src_file)) {
    file.copy(src_file, "BRCA_DEGS.csv", overwrite = TRUE)
} else {
    # Fallback synthetic data matching the expected format
    df <- data.frame(
        X = c("BRCA1", "BRCA2", "TP53", "PTEN", "EGFR", "MYC"),
        logFC = c(1.5, -2.1, 0.8, -1.2, 2.5, 3.1),
        adj.P.Val = c(0.01, 0.005, 0.04, 0.001, 0.0002, 0.0001)
    )
    write.csv(df, "BRCA_DEGS.csv", row.names = FALSE)
}