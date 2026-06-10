library(ribor)

src_file <- system.file("extdata", "HEK293_ingolia.ribo", package = "ribor")

if (file.exists(src_file)) {
    file.copy(src_file, "HEK293_ingolia.ribo", overwrite = TRUE)
} else {
    stop("Source file HEK293_ingolia.ribo not found in ribor package.")
}