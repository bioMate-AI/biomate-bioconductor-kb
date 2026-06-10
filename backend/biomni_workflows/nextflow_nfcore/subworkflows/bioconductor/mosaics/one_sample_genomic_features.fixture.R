library(mosaics)
library(mosaicsExample)

files_to_copy <- c("chip_chr21.txt", "M_chr21.txt", "GC_chr21.txt", "N_chr21.txt")

for (f in files_to_copy) {
    src <- system.file("extdata", f, package="mosaicsExample")
    if (src != "" && file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        coords <- seq(10000000, 10005000, by=200)
        n_bins <- length(coords)
        if (f == "chip_chr21.txt") {
            df <- data.frame(chr = rep("chr21", n_bins), coord = coords, count = rpois(n_bins, 5))
        } else if (f == "M_chr21.txt") {
            df <- data.frame(chr = rep("chr21", n_bins), coord = coords, score = runif(n_bins, 0, 1))
        } else if (f == "GC_chr21.txt") {
            df <- data.frame(chr = rep("chr21", n_bins), coord = coords, score = runif(n_bins, 0.3, 0.7))
        } else if (f == "N_chr21.txt") {
            df <- data.frame(chr = rep("chr21", n_bins), coord = coords, score = sample(0:1, n_bins, replace=TRUE))
        }
        write.table(df, f, row.names=FALSE, col.names=FALSE, quote=FALSE, sep="\t")
    }
}