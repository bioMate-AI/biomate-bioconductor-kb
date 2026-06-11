library(ribor)

src_file <- system.file("extdata", "HEK293_ingolia.ribo", package = "ribor")

if (file.exists(src_file)) {
    file.copy(src_file, "HEK293_ingolia.ribo", overwrite = TRUE)
} else {
    files <- list.files(system.file("extdata", package = "ribor"), 
                        pattern = "HEK293_ingolia\\.ribo$", 
                        recursive = TRUE, 
                        full.names = TRUE)
    if (length(files) > 0) {
        file.copy(files[1], "HEK293_ingolia.ribo", overwrite = TRUE)
    } else {
        stop("HEK293_ingolia.ribo not found in ribor package.")
    }
}