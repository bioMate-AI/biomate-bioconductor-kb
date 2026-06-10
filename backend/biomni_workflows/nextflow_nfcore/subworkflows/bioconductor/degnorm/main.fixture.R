library(DegNorm)

bam_src <- list.files(path = system.file("extdata", package = "DegNorm"), pattern = "\\.bam$", full.names = TRUE)
for (b in bam_src) {
    file.copy(b, basename(b), overwrite = TRUE)
    bai <- paste0(b, ".bai")
    if (file.exists(bai)) {
        file.copy(bai, basename(bai), overwrite = TRUE)
    }
}

gtf_src <- list.files(path = system.file("extdata", package = "DegNorm"), pattern = "\\.gtf$", full.names = TRUE)
for (g in gtf_src) {
    file.copy(g, basename(g), overwrite = TRUE)
}