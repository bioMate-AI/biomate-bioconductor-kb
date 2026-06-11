library(MiChip)

datadir <- system.file("extdata", package="MiChip")
input_files <- c("B_676.gpr", "B_677.gpr")

for (f in input_files) {
    src <- list.files(datadir, pattern = f, recursive = TRUE, full.names = TRUE)
    if (length(src) > 0) {
        file.copy(src[1], f, overwrite = TRUE)
    } else {
        stop(paste("Required input file not found in package extdata:", f))
    }
}