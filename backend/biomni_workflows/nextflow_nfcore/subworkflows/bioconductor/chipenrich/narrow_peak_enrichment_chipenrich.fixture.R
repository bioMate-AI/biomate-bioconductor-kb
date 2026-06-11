library(chipenrich)

# Load the peaks data from the companion package
data(peaks_E2F4, package = 'chipenrich.data')

# Write peaks_E2F4 to a file (BED-like format: no header or commented header, first 3 cols are chr, start, end)
write.table(
  peaks_E2F4[, c("chrom", "start", "end")], 
  file = "peaks_E2F4", 
  sep = "\t", 
  quote = FALSE, 
  row.names = FALSE, 
  col.names = FALSE
)

# Create a custom gene sets file (tab-delimited text file)
# chipenrich custom gene sets typically require a 2-column format mapping geneset IDs to gene IDs
custom_genesets <- data.frame(
  geneset_id = c("CustomSet_1", "CustomSet_1", "CustomSet_2", "CustomSet_2"),
  gene_id = c("148398", "57801", "148398", "1000")
)

write.table(
  custom_genesets, 
  file = "vignette_genesets.txt", 
  sep = "\t", 
  quote = FALSE, 
  row.names = FALSE, 
  col.names = TRUE
)