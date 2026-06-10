library(oncoscanR)

chas_example_path <- system.file("extdata", "chas_example.txt", package = "oncoscanR")

if (file.exists(chas_example_path)) {
    file.copy(chas_example_path, "chas_file.txt", overwrite = TRUE)
} else {
    # Fallback: create a minimal synthetic ChAS export file if the example is missing
    # The file must contain 'Type', 'CN State', and 'Full Location' columns.
    chas_data <- data.frame(
        Type = c("Gain", "Loss", "LOH"),
        `CN State` = c(3, 1, 2),
        `Full Location` = c("chr1:144009053-249212878", "chr5:38139-46193462", "chr17:1000000-2000000"),
        check.names = FALSE
    )
    write.table(chas_data, "chas_file.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}