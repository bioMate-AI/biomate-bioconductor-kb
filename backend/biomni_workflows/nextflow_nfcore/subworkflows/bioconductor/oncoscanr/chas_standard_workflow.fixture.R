library(oncoscanR)

chas.fn <- system.file("extdata", "chas_example.txt", package = "oncoscanR")

if (file.exists(chas.fn)) {
    file.copy(chas.fn, "chas_file.txt", overwrite = TRUE)
} else {
    chas_data <- data.frame(
        "Type" = c("Gain", "Loss", "LOH"),
        "CN State" = c("3", "1", "2"),
        "Full Location" = c("chr1:144009053-249212878", "chr2:100000-5000000", "chr3:100000-6000000"),
        check.names = FALSE
    )
    write.table(chas_data, "chas_file.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}