library(chipenrich)
library(chipenrich.data)

# 1. Prepare peaks_H3K4me3_GM12878.bed
# Load the dataset exactly as shown in the vignette
data(peaks_H3K4me3_GM12878, package = 'chipenrich.data')

# Write to BED format (tab-delimited, no header or row names as per BED spec)
write.table(peaks_H3K4me3_GM12878, file = "peaks_H3K4me3_GM12878.bed", 
            sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

# 2. Prepare vignette_genesets.txt
# Create a synthetic custom gene sets file. chipenrich expects a tab-delimited 
# file with 'gene_id' and 'set_id' columns for custom gene sets.
custom_genesets <- data.frame(
  gene_id = c("148398", "57801", "148398", "57801"),
  set_id = c("Set1", "Set1", "Set2", "Set2")
)

write.table(custom_genesets, file = "vignette_genesets.txt", 
            sep = "\t", quote = FALSE, row.names = FALSE)