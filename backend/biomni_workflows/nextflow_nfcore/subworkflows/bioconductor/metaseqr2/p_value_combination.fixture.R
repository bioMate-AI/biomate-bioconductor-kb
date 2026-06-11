library(metaseqR2)

# Construct a synthetic data frame of p-values from multiple statistical algorithms
# matching the expected format (tab-separated, header=TRUE, row.names=1)
set.seed(123)
genes <- paste0("ENSG00000", 100000 + 1:20)
hg19pvalues <- data.frame(
    DESeq2 = runif(20, 0, 1),
    edgeR = runif(20, 0, 1),
    limma = runif(20, 0, 1),
    NOISeq = runif(20, 0, 1),
    row.names = genes
)

# Write the data frame to the exact file name expected by the workflow
write.table(
    hg19pvalues, 
    file = "hg19pvalues", 
    sep = "\t", 
    quote = FALSE, 
    row.names = TRUE, 
    col.names = NA
)