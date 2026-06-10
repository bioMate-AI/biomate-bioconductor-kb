library(Rsubread)
src_file <- system.file("extdata", "reads.txt.gz", package="Rsubread")
if (file.exists(src_file)) {
    file.copy(src_file, "reads.txt.gz", overwrite = TRUE)
} else {
    gz <- gzfile("reads.txt.gz", "w")
    writeLines(c("@read1", "ACGT", "+", "IIII"), gz)
    close(gz)
}