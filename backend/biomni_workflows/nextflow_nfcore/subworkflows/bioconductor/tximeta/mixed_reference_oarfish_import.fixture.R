library(tximeta)
library(GenomicRanges)

quant_data <- data.frame(
  tname = c("tx1", "tx2"),
  len = c(1000, 2000),
  num_reads = c(10, 20)
)
gz1 <- gzfile("sgnex_h9_rep2.quant.gz", "w")
write.table(quant_data, gz1, sep="\t", quote=FALSE, row.names=FALSE)
close(gz1)

coldata <- data.frame(
  files = "sgnex_h9_rep2.quant.gz",
  names = "sgnex_h9_rep2",
  condition = "A",
  stringsAsFactors = FALSE
)
write.csv(coldata, "coldata", row.names=FALSE)

novel_gr <- GRanges(
  seqnames = "chr1",
  ranges = IRanges(start = c(1, 2000), end = c(1000, 3000)),
  strand = c("+", "-"),
  tx_id = c("tx1", "tx2"),
  gene_id = c("gene1", "gene2")
)
saveRDS(novel_gr, "novel_gr")