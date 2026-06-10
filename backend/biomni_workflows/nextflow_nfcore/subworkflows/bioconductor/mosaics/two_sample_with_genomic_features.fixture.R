library(mosaics)
if (requireNamespace("mosaicsExample", quietly = TRUE)) {
    library(mosaicsExample)
}

files_to_copy <- c(
    "chip_chr21.txt",
    "input_chr21.txt",
    "M_chr21.txt",
    "GC_chr21.txt",
    "N_chr21.txt"
)

for (f in files_to_copy) {
    src <- system.file("extdata", f, package="mosaicsExample")
    if (src == "" || !file.exists(src)) {
        src <- system.file("extdata", f, package="mosaics")
    }
    
    if (src != "" && file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        # Fallback to creating dummy files if the package doesn't have them
        # mosaics bin files typically have 3 columns: chr, coord, count/score
        df <- data.frame(
            chr = rep("chr21", 10),
            coord = seq(10000, by = 200, length.out = 10),
            val = if (f %in% c("chip_chr21.txt", "input_chr21.txt")) rpois(10, 5) else runif(10)
        )
        write.table(df, file = f, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
    }
}