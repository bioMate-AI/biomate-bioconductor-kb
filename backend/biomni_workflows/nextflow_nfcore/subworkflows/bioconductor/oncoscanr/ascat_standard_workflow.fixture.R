library(oncoscanR)

ascat_example <- system.file("extdata", "ascat_example.txt", package = "oncoscanR")

if (file.exists(ascat_example)) {
    file.copy(ascat_example, "ascat_file.txt", overwrite = TRUE)
} else {
    # Construct a synthetic ASCAT file matching the vignette's specification
    ascat_data <- data.frame(
        chr = c("1", "5"),
        startpos = c(144009053, 38139),
        endpos = c(249212878, 46193462),
        nMajor = c(2, 2),
        nMinor = c(1, 1)
    )
    write.table(ascat_data, "ascat_file.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}