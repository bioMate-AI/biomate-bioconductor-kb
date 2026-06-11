library(segmentSeq)

datadir <- system.file("extdata", package = "segmentSeq")
libfiles <- c("SL9.txt", "SL10.txt", "SL26.txt", "SL32.txt")

for (f in libfiles) {
    src <- file.path(datadir, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        # Fallback in case the file is missing from extdata
        cat("chr\tloc\tstrand\ttag\n>Chr1\t265\t-\tAAATGAAGATAAACCATCCA\n>Chr1\t405\t-\tAAGGAGTAAGAATGACAATA\n", file = f)
    }
}