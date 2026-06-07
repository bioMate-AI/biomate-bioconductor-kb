# Test: limma-voom RNA-seq differential expression
library(limma)
library(edgeR)

# 1. Simulate RNA-seq count data
set.seed(42)
n_genes <- 200; n_samples <- 8
group <- factor(c("ctrl","ctrl","ctrl","ctrl","treat","treat","treat","treat"))
counts <- matrix(rnbinom(n_genes * n_samples, mu = 50, size = 3),
                 nrow = n_genes,
                 dimnames = list(paste0("Gene", seq_len(n_genes)),
                                paste0("Samp", seq_len(n_samples))))
counts[1:30, 5:8] <- counts[1:30, 5:8] * 4  # 30 DE genes

# 2. Create DGEList and normalize
dge <- DGEList(counts = counts, group = group)
keep <- filterByExpr(dge, group = group)
dge <- dge[keep,, keep.lib.sizes = FALSE]
dge <- calcNormFactors(dge)
cat("After filtering:", nrow(dge), "genes\n")

# 3. Design matrix and voom transformation
design <- model.matrix(~ group)
v <- voom(dge, design, plot = FALSE)
cat("voom: weights computed for", nrow(v), "genes\n")
stopifnot(!is.null(v$weights))

# 4. Fit linear model and apply eBayes
fit <- lmFit(v, design)
fit <- eBayes(fit)
cat("eBayes moderation applied\n")
stopifnot(!is.null(fit$t))

# 5. Get top DE genes
tt <- topTable(fit, coef = 2, n = Inf, sort.by = "P")
cat("Significant genes (adj.P < 0.05):", sum(tt$adj.P.Val < 0.05), "\n")
stopifnot(all(c("logFC","adj.P.Val","t") %in% colnames(tt)))

# 6. Venn diagram of DE calls
results <- decideTests(fit)
cat("DE calls summary:\n")
print(summary(results))

write.csv(tt, "test_results_limma.csv")
cat("Test PASSED: limma-voom workflow complete\n")
