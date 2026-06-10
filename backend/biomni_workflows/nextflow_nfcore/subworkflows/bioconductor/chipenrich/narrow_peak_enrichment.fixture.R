library(chipenrich)
library(chipenrich.data)

# 1. Generate peaks_E2F4.bed
# Load the dataset exactly as shown in the vignette
data(peaks_E2F4, package = 'chipenrich.data')

# Write to BED format (tab-delimited, no header, no row names)
write.table(
  peaks_E2F4, 
  file = "peaks_E2F4.bed", 
  sep = "\t", 
  quote = FALSE, 
  row.names = FALSE, 
  col.names = FALSE
)

# 2. Generate vignette_genesets.txt
# Create a synthetic custom gene sets file (tab-delimited with gene_id and set_id columns)
custom_genesets <- data.frame(
  gene_id = c("148398", "57801", "148398", "1000", "2000"),
  set_id = c("GS_A", "GS_A", "GS_B", "GS_B", "GS_C"),
  stringsAsFactors = FALSE
)

write.table(
  custom_genesets, 
  file = "vignette_genesets.txt", 
  sep = "\t", 
  quote = FALSE, 
  row.names = FALSE, 
  col.names = TRUE
)