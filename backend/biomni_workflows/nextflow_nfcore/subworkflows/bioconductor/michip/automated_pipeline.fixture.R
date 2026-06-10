library(MiChip)

datadir <- system.file("extdata", package="MiChip")
gpr_files <- c("B_676.gpr", "B_677.gpr")

for (f in gpr_files) {
    src <- file.path(datadir, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        found <- list.files(datadir, pattern = f, recursive = TRUE, full.names = TRUE)
        if (length(found) > 0) {
            file.copy(found[1], f, overwrite = TRUE)
        }
    }
}