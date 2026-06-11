library(metaseqR2)
data("hg19pvalues", package = "metaseqR2")
write.table(hg19pvalues, file = "hg19pvalues", sep = "\t", quote = FALSE, row.names = TRUE)