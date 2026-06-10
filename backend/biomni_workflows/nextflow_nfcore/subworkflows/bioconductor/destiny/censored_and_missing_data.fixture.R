suppressPackageStartupMessages({
    library(destiny)
})

extdata_dir <- system.file("extdata", package = "destiny")

# Find and copy raw_ct.xls
raw_ct_files <- list.files(extdata_dir, pattern = "raw_ct\\.xls$", recursive = TRUE, full.names = TRUE)
if (length(raw_ct_files) > 0) {
    file.copy(raw_ct_files[1], "raw_ct.xls", overwrite = TRUE)
} else {
    # Fallback: create a dummy file if not found
    dummy_raw <- data.frame(
        Cell = c("1C 1", "1C 2", "1C 3", "1C 4", "1C 5"),
        Actb = c(14.0, 13.7, 13.4, 13.7, 13.5),
        Ahcy = c(19.3, 18.6, 18.2, 18.6, 18.6),
        Aqp3 = c(23.9, 28.0, 26.2, 28.0, 24.2),
        Atp12a = c(28.0, 28.0, 28.0, 28.0, 28.0)
    )
    write.table(dummy_raw, "raw_ct.xls", sep = "\t", row.names = FALSE, quote = FALSE)
}

# Find and copy mmc6.xls
mmc6_files <- list.files(extdata_dir, pattern = "mmc6\\.xls$", recursive = TRUE, full.names = TRUE)
if (length(mmc6_files) > 0) {
    file.copy(mmc6_files[1], "mmc6.xls", overwrite = TRUE)
} else {
    # Fallback: create a dummy file if not found
    dummy_mmc6 <- data.frame(
        Dilution = c(1, 0.5, 0.25, 0.125),
        Ct = c(15.0, 16.0, 17.0, 18.0)
    )
    write.table(dummy_mmc6, "mmc6.xls", sep = "\t", row.names = FALSE, quote = FALSE)
}