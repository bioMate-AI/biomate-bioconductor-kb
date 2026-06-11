library(epidecodeR)

events_file <- system.file("extdata", "NOMO-1_ref_peaks.bed", package="epidecodeR")
deg_file <- system.file("extdata", "FTOi.txt", package="epidecodeR")

if (file.exists(events_file)) {
    file.copy(events_file, "NOMO-1_ref_peaks.bed", overwrite = TRUE)
} else {
    # Fallback synthetic data if the file is missing
    peaks_df <- data.frame(
        V1 = c("chr1", "chr1", "chr1"),
        V2 = c(133350, 856249, 904833),
        V3 = c(133500, 856749, 915757),
        V4 = c("ENSG00000233750.3", "ENSG00000228794.9", "ENSG00000272438.1"),
        V5 = c(1.8e-03, 1.0e-28, 1.8e-04),
        V6 = c("+", "+", "+")
    )
    write.table(peaks_df, "NOMO-1_ref_peaks.bed", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}

if (file.exists(deg_file)) {
    file.copy(deg_file, "FTOi.txt", overwrite = TRUE)
} else {
    # Fallback synthetic data if the file is missing
    deg_df <- data.frame(
        ID = c("ENSG00000233750.3", "ENSG00000228794.9", "ENSG00000272438.1"),
        log2FC = c(1.5, -2.1, 0.5),
        Pvalue = c(0.01, 0.001, 0.04)
    )
    write.table(deg_df, "FTOi.txt", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)
}