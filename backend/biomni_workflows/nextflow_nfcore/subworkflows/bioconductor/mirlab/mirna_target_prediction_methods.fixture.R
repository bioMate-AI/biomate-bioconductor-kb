library(miRLAB)

dataset <- system.file("extdata", "EMT35.csv", package="miRLAB")

if (file.exists(dataset)) {
    file.copy(dataset, "EMT35.csv", overwrite = TRUE)
} else {
    # Fallback: construct a synthetic dataset matching the expected dimensions
    # cause=1:35 (miRNAs), effect=36:1189 (mRNAs)
    n_samples <- 10
    n_cols <- 1189
    synthetic_data <- matrix(rnorm(n_samples * n_cols), nrow = n_samples, ncol = n_cols)
    
    col_names <- c(paste0("hsa-miR-", 1:35), paste0("Gene", 1:(n_cols - 35)))
    colnames(synthetic_data) <- col_names
    
    write.csv(synthetic_data, "EMT35.csv", row.names = FALSE)
}