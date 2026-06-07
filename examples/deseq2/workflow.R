# Test: DESeq2 differential expression analysis
# Data: simulated RNA-seq counts (makeExampleDESeqDataSet)
# Expected: DESeqResults object with log2FoldChange and padj
library(DESeq2)

# 1. Create example dataset (1000 genes, 6 samples: 3 control, 3 treated)
set.seed(42)
dds <- makeExampleDESeqDataSet(n = 1000, m = 6)
dds$condition <- factor(c("control","control","control","treated","treated","treated"))
design(dds) <- ~ condition

# 2. Pre-filter low-count genes (keep rows with >= 10 counts total)
keep <- rowSums(counts(dds)) >= 10
dds <- dds[keep, ]
cat("Genes after filtering:", nrow(dds), "\n")
stopifnot(nrow(dds) >= 200)

# 3. Run DESeq2 differential expression
dds <- DESeq(dds)

# 4. Extract results (treated vs. control)
res <- results(dds, contrast = c("condition", "treated", "control"))
cat("DE results summary:\n")
summary(res)

# 5. Shrink LFC estimates (apeglm)
res_shrunk <- lfcShrink(dds, coef = 2, type = "apeglm")
cat("Significant genes (padj < 0.05):",
    sum(res_shrunk$padj < 0.05, na.rm = TRUE), "\n")
stopifnot(sum(!is.na(res_shrunk$padj)) > 0)

# 6. Variance-stabilizing transformation for PCA
# vst() requires >= 1000 genes; use varianceStabilizingTransformation otherwise
if (nrow(dds) >= 1000) {
  vsd <- vst(dds, blind = FALSE)
} else {
  vsd <- varianceStabilizingTransformation(dds, blind = FALSE)
}
pca_data <- plotPCA(vsd, returnData = TRUE)
cat("PCA computed for", nrow(pca_data), "samples\n")
stopifnot(nrow(pca_data) == 6)

# 7. Save results
write.csv(as.data.frame(res_shrunk), "test_results_DESeq2.csv")
cat("Test PASSED: DESeq2 workflow complete\n")
