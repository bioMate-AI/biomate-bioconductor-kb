library(regioneR)

files_to_copy <- c("my.special.genes.txt", "all.genes.txt", "my.altered.regions.txt")

for (f in files_to_copy) {
    src <- system.file("extdata", f, package = "regioneR")
    if (src != "" && file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        # Fallback synthetic data if the package does not ship them
        if (f == "my.special.genes.txt") {
            df <- data.frame(chr = "chr1", start = seq(1000, 10000, by = 1000), end = seq(1500, 10500, by = 1000))
            write.table(df, f, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
        } else if (f == "all.genes.txt") {
            df <- data.frame(chr = "chr1", start = seq(1000, 100000, by = 1000), end = seq(1500, 100500, by = 1000))
            write.table(df, f, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
        } else if (f == "my.altered.regions.txt") {
            df <- data.frame(chr = "chr1", start = c(2000, 5000), end = c(2500, 5500))
            write.table(df, f, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
        }
    }
}