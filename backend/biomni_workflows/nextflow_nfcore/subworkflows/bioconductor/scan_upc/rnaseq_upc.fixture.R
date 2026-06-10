library(scan_upc)

set.seed(123)
genes <- paste0("Gene", 1:100)
samples <- paste0("Sample", 1:4)
expr_data <- matrix(runif(400, min=0, max=1000), nrow=100, ncol=4)
rownames(expr_data) <- genes
colnames(expr_data) <- samples

write.table(expr_data, file="expression_matrix.txt", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)