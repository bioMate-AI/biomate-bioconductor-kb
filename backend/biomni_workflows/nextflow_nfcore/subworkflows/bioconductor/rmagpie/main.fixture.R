# Real user-style input for Rmagpie (RFE-SVM molecular classification):
#   ExpressionSet.rds - an ExpressionSet of gene expression for a labelled
#       training cohort. phenoData carries a two-class outcome (the classification
#       target, e.g. good vs poor prognosis). A marker-gene subset separates the
#       classes so RFE-SVM has real signal to select.
#   vV_newSamples.txt - a tab-delimited expression table for NEW (unlabelled)
#       samples over the SAME genes, to be classified by the trained model.
# This is exactly what a user supplies to Rmagpie; no package demo data.

suppressPackageStartupMessages(library(Biobase))

set.seed(123)
n_genes  <- 70
n_train  <- 40
gene_ids <- sprintf("Gene%02d", seq_len(n_genes))

class <- factor(rep(c("good", "poor"), each = n_train / 2), levels = c("good", "poor"))
sig <- 1:20                                   # discriminative genes
mat <- matrix(rnorm(n_genes * n_train, mean = 0, sd = 1), nrow = n_genes)
poor <- which(class == "poor")
mat[sig, poor] <- mat[sig, poor] + 2
rownames(mat) <- gene_ids
colnames(mat) <- sprintf("train%02d", seq_len(n_train))

pheno <- data.frame(class = class, row.names = colnames(mat))
vd <- data.frame(labelDescription = "Two-class prognosis outcome",
                 row.names = "class")
eset <- ExpressionSet(assayData = mat,
                      phenoData = AnnotatedDataFrame(pheno, vd))
saveRDS(eset, "ExpressionSet.rds")

# New samples to classify (same genes, unlabelled) -- a mix of both classes
n_new <- 6
new <- matrix(rnorm(n_genes * n_new, mean = 0, sd = 1), nrow = n_genes)
new[sig, 4:6] <- new[sig, 4:6] + 2            # last three look "poor"
rownames(new) <- gene_ids
colnames(new) <- sprintf("new%d", seq_len(n_new))
write.table(new, "vV_newSamples.txt", sep = "\t", quote = FALSE, col.names = NA)
