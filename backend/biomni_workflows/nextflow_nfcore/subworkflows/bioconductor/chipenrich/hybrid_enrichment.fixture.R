library(chipenrich)

# Load the peaks_E2F4 dataset from the companion package
data(peaks_E2F4, package = 'chipenrich.data')

# Write the peaks data.frame to a tab-delimited file named 'peaks_E2F4'
write.table(
  peaks_E2F4, 
  file = "peaks_E2F4", 
  sep = "\t", 
  quote = FALSE, 
  row.names = FALSE
)

# Create a synthetic custom gene sets file 'vignette_genesets.txt'
# chipenrich custom gene sets require a tab-delimited file with 'gene_id' and 'set_id' columns
custom_genesets <- data.frame(
  gene_id = c("148398", "57801", "148398", "1000", "2000"),
  set_id = c("Set1", "Set1", "Set2", "Set2", "Set3"),
  stringsAsFactors = FALSE
)

write.table(
  custom_genesets, 
  file = "vignette_genesets.txt", 
  sep = "\t", 
  quote = FALSE, 
  row.names = FALSE
)