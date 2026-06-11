library(RIVER)

src_file <- system.file("extdata", "simulation_RIVER.gz", package="RIVER")
if (file.exists(src_file)) {
    file.copy(src_file, "simulation_RIVER.gz", overwrite = TRUE)
} else {
    stop("Could not find simulation_RIVER.gz in RIVER package")
}