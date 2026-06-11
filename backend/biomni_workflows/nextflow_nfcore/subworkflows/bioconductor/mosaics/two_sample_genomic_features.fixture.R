suppressPackageStartupMessages({
    library(mosaics)
    library(mosaicsExample)
})

files_to_copy <- c(
    "chip_chr21.txt",
    "input_chr21.txt",
    "M_chr21.txt",
    "GC_chr21.txt",
    "N_chr21.txt"
)

for (f in files_to_copy) {
    src <- system.file("extdata", f, package="mosaicsExample")
    if (src != "" && file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        # Fallback dummy data if the ExperimentData package is missing or incomplete
        chr <- rep("chr21", 100)
        coord <- seq(1000000, by=200, length.out=100)
        if (f == "chip_chr21.txt") {
            val <- rpois(100, 5)
        } else if (f == "input_chr21.txt") {
            val <- rpois(100, 2)
        } else if (f == "M_chr21.txt") {
            val <- runif(100, 0, 1)
        } else if (f == "GC_chr21.txt") {
            val <- runif(100, 0.3, 0.6)
        } else if (f == "N_chr21.txt") {
            val <- sample(0:1, 100, replace=TRUE)
        }
        df <- data.frame(chr=chr, coord=coord, val=val)
        write.table(df, file=f, sep="\t", row.names=FALSE, col.names=FALSE, quote=FALSE)
    }
}