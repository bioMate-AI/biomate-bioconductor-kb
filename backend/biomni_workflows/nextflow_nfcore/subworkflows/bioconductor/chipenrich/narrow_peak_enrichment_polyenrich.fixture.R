library(chipenrich)
library(chipenrich.data)

data(peaks_E2F4, package = 'chipenrich.data')
write.table(peaks_E2F4, file = "peaks_E2F4", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

custom_genesets <- data.frame(
  geneset_id = c("Set1", "Set1", "Set2", "Set2"),
  gene_id = c("148398", "57801", "148398", "1000")
)
write.table(custom_genesets, file = "vignette_genesets.txt", sep = "\t", quote = FALSE, row.names = FALSE)