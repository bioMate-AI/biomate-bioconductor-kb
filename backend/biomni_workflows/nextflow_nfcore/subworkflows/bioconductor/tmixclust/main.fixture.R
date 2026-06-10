library(TMixClust)

toy_data_file <- system.file("extdata", "toy_time_series.txt", package = "TMixClust")

if (toy_data_file != "" && file.exists(toy_data_file)) {
    file.copy(toy_data_file, "toy_time_series.txt", overwrite = TRUE)
} else {
    data("toy_data_df", package = "TMixClust")
    write.table(toy_data_df, file = "toy_time_series.txt", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
}