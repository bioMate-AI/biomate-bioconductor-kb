library(HiLDA)
library(selectKSigs)

inputFile <- system.file("extdata/esophageal.mp.txt.gz", package="HiLDA")

if (file.exists(inputFile)) {
    file.copy(inputFile, "esophageal.mp.txt.gz", overwrite = TRUE)
} else {
    # Fallback synthetic data based on vignette's Mutation Position Format
    df <- data.frame(
        sample = c("sample1", "sample1", "sample1", "sample2", "sample3"),
        chr = c("chr1", "chr1", "chr2", "chr1", "chr3"),
        pos = c(100, 200, 100, 300, 400),
        ref = c("A", "A", "G", "T", "T"),
        alt = c("C", "T", "T", "C", "C")
    )
    gz1 <- gzfile("esophageal.mp.txt.gz", "w")
    write.table(df, gz1, sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
    close(gz1)
}