library(chipenrich)
library(chipenrich.data)

# 1. Load the peaks data from the companion package as shown in the vignette
data(peaks_E2F4, package = 'chipenrich.data')

# 2. Write the peaks to a BED file (no header, tab-separated) to match the read excerpt
write.table(peaks_E2F4[, c("chrom", "start", "end")], 
            file = "peaks_E2F4.bed", 
            sep = "\t", 
            row.names = FALSE, 
            col.names = FALSE, 
            quote = FALSE)

# 3. Construct a synthetic custom gene sets file
# chipenrich custom gene sets typically require a tab-delimited file 
# with columns for geneset_id and gene_id.
synthetic_genesets <- data.frame(
  geneset_id = c("GS_A", "GS_A", "GS_B", "GS_B", "GS_B"),
  gene_id = c("148398", "57801", "148398", "1000", "2000"),
  stringsAsFactors = FALSE
)

write.table(synthetic_genesets, 
            file = "vignette_genesets.txt", 
            sep = "\t", 
            row.names = FALSE, 
            col.names = TRUE, 
            quote = FALSE)