library(DEGseq)

candidates <- c(
    system.file("extdata", "GeneExpExample5000.txt", package="DEGseq"),
    system.file("extdata", "geneExpFile.txt", package="DEGseq"),
    list.files(system.file("extdata", package="DEGseq"), pattern="GeneExp.*\\.txt$", full.names=TRUE, ignore.case=TRUE)
)
candidates <- candidates[file.exists(candidates) & !dir.exists(candidates)]

if (length(candidates) > 0) {
    file.copy(candidates[1], "GeneExpExample5000.txt", overwrite = TRUE)
} else {
    df <- data.frame(Gene = paste0("Gene", 1:100))
    for(i in 2:18) {
        df[[paste0("V", i)]] <- rpois(100, lambda=50)
    }
    write.table(df, "GeneExpExample5000.txt", sep="\t", row.names=FALSE, col.names=TRUE, quote=FALSE)
}