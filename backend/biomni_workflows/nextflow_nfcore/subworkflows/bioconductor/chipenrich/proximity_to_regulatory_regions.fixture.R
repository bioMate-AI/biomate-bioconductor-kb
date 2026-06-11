library(chipenrich)
library(chipenrich.data)

# 1. peaks_E2F4
# Load the dataset from the companion package
data(peaks_E2F4, package = 'chipenrich.data')

# Write to a file named "peaks_E2F4". 
# The vignette specifies that files without standard extensions are supported 
# if the first 3 columns are chr, start, and end, and there is no header.
write.table(peaks_E2F4, file = "peaks_E2F4", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

# 2. vignette_genesets.txt
# Create a synthetic custom gene sets file (tab-delimited text file)
custom_genesets <- data.frame(
  geneset_id = c("gs1", "gs1", "gs2", "gs2", "gs3"),
  gene_id = c("148398", "57801", "148398", "1000", "840040")
)

write.table(custom_genesets, file = "vignette_genesets.txt", sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)