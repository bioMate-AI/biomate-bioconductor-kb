library(oncoscanR)

# 1. Prepare and write ascat_example.txt
ascat_src <- system.file("extdata", "ascat_example.txt", package = "oncoscanR")
if (ascat_src != "" && file.exists(ascat_src)) {
    file.copy(ascat_src, "ascat_example.txt", overwrite = TRUE)
} else {
    # Fallback to synthetic data matching the vignette's structure
    ascat_data <- data.frame(
        chr = c("1", "5"),
        startpos = c(144009053, 38139),
        endpos = c(249212878, 46193462),
        nMajor = c(2, 2),
        nMinor = c(1, 1)
    )
    write.table(ascat_data, "ascat_example.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

# 2. Prepare and write oncoscan_na33.cov
# The object is provided by the package; we serialize it to RDS as requested.
if (!exists("oncoscan_na33.cov")) {
    data("oncoscan_na33.cov", package = "oncoscanR")
}
saveRDS(oncoscan_na33.cov, "oncoscan_na33.cov")