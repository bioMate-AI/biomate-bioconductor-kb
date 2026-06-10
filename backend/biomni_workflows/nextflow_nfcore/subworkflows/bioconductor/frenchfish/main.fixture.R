library(frenchFISH)

src_file <- system.file("extdata", "SampleFISH.jpg_data.csv", package="frenchFISH")

if (file.exists(src_file)) {
    file.copy(src_file, "SampleFISH.jpg_data.csv", overwrite = TRUE)
} else {
    # Fallback synthetic data matching FISHalyseR output format
    set.seed(366)
    dummy_data <- data.frame(
        Area = runif(44, 100, 500),
        R = rpois(44, 20),
        G = rpois(44, 20)
    )
    write.csv(dummy_data, "SampleFISH.jpg_data.csv", row.names = FALSE)
}