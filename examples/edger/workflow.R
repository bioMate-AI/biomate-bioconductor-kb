# Test: edgeR differential expression (quasi-likelihood F-test)
# Data: Simulated RNA-seq counts (6 samples, 200 genes)
library(edgeR)

# 1. Simulate count data
set.seed(42)
n_genes <- 200; n_samples <- 6
group <- factor(c("A","A","A","B","B","B"))
counts <- matrix(rnbinom(n_genes * n_samples, mu = 100, size = 5),
                 nrow = n_genes,
                 dimnames = list(paste0("Gene", seq_len(n_genes)),
                                paste0("Sample", seq_len(n_samples))))
# Make 20 genes differentially expressed
counts[1:20, 4:6] <- counts[1:20, 4:6] * 3

# 2. Create DGEList object
dge <- DGEList(counts = counts, group = group)
cat("DGEList created:", nrow(dge), "genes x", ncol(dge), "samples\n")
stopifnot(nrow(dge) == n_genes, ncol(dge) == n_samples)

# 3. Filter lowly expressed genes
keep <- filterByExpr(dge, group = group)
dge <- dge[keep, , keep.lib.sizes = FALSE]
cat("Genes after filterByExpr:", nrow(dge), "\n")

# 4. Normalize library sizes (TMM)
dge <- calcNormFactors(dge, method = "TMM")
cat("TMM norm factors:", round(dge$samples$norm.factors, 3), "\n")

# 5. Estimate dispersion
design <- model.matrix(~ group)
dge <- estimateDisp(dge, design)
cat("Common dispersion:", round(dge$common.dispersion, 4), "\n")
stopifnot(!is.na(dge$common.dispersion))

# 6. Fit quasi-likelihood model and test
fit <- glmQLFit(dge, design)
res <- glmQLFTest(fit, coef = 2)
tt  <- topTags(res, n = Inf)$table
cat("Significant DE genes (FDR < 0.05):", sum(tt$FDR < 0.05), "\n")
stopifnot(nrow(tt) > 0)
stopifnot(all(c("logFC","FDR","PValue") %in% colnames(tt)))

# 7. Save results
write.csv(tt, "test_results_edgeR.csv")
cat("Test PASSED: edgeR workflow complete\n")
