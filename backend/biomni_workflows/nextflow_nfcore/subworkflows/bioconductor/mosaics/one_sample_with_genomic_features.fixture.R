library("mosaics")
library("mosaicsExample")

files_to_copy <- c("chip_chr21.txt", "M_chr21.txt", "GC_chr21.txt", "N_chr21.txt")

for (f in files_to_copy) {
    src <- system.file("extdata", f, package="mosaicsExample")
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        # Fallback in case the files are shipped in the main package
        src2 <- system.file("extdata", f, package="mosaics")
        if (file.exists(src2)) {
            file.copy(src2, f, overwrite = TRUE)
        } else {
            stop(paste("Required input file not found in package extdata:", f))
        }
    }
}