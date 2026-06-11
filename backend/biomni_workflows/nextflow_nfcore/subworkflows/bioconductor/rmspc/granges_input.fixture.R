library(rmspc)

path <- system.file("extdata", package = "rmspc")
input1 <- file.path(path, "rep1.bed")
input2 <- file.path(path, "rep2.bed")

if (file.exists(input1)) {
    file.copy(input1, "GR1", overwrite = TRUE)
} else {
    df1 <- data.frame(chr = "chr1", start = 10000, end = 10500, name = "peak1", score = 10)
    write.table(df1, "GR1", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
}

if (file.exists(input2)) {
    file.copy(input2, "GR2", overwrite = TRUE)
} else {
    df2 <- data.frame(chr = "chr1", start = 10200, end = 10700, name = "peak2", score = 15)
    write.table(df2, "GR2", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
}