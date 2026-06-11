library(EDASeq)
library(yeastRNASeq)

data(geneLevelData)
data(yeastGC)
data(yeastLength)

filter <- apply(geneLevelData, 1, function(x) mean(x) > 10)
common <- intersect(names(yeastGC), rownames(geneLevelData[filter, ]))

counts_out <- geneLevelData[common, ]
feature <- data.frame(gc = yeastGC, length = yeastLength)
metadata_out <- feature[common, ]

write.table(counts_out, file = "gene_counts.tsv", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
write.table(metadata_out, file = "gene_metadata.tsv", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)