library(RIVER)

input_file <- "simulation_RIVER.gz"
src_file <- system.file("extdata", "simulation_RIVER.gz", package="RIVER")

if (file.exists(src_file)) {
    file.copy(src_file, input_file, overwrite = TRUE)
} else {
    stop("Could not find simulation_RIVER.gz in the RIVER package extdata directory.")
}