# Real user-style input for affycoretools::makeVenn / vennInLine:
#   fit2.rds    - a limma MArrayLM fit (after contrasts.fit + eBayes) computed
#                 from the user's own expression matrix.
#   contrast.rds- the contrast matrix (>=2 columns, because the workflow's
#                 collist = list(1:2) compares the first TWO contrasts in a Venn).
#   design.rds  - the design matrix used for the fit.
# We build a small two-group-with-two-comparisons expression experiment and run
# the standard limma pipeline so fit2/contrast/design are genuine analysis
# objects (not a packaged demo fit). No package demo data.

suppressPackageStartupMessages({
  library(Biobase)
  library(limma)
})

set.seed(123)
n_genes <- 500
# Three groups (Control, TreatA, TreatB), 6 samples each -> two contrasts vs Control
groups <- factor(rep(c("Control", "TreatA", "TreatB"), each = 6),
                 levels = c("Control", "TreatA", "TreatB"))
n_samp <- length(groups)

mat <- matrix(rnorm(n_genes * n_samp, mean = 7, sd = 1), nrow = n_genes)
# TreatA up-regulates genes 1:60; TreatB up-regulates genes 40:120 (overlap -> Venn)
mat[1:60,  groups == "TreatA"] <- mat[1:60,  groups == "TreatA"] + 2
mat[40:120, groups == "TreatB"] <- mat[40:120, groups == "TreatB"] + 2
rownames(mat) <- sprintf("Gene%03d", seq_len(n_genes))
colnames(mat) <- sprintf("S%02d", seq_len(n_samp))

eset <- ExpressionSet(assayData = mat,
                      phenoData = AnnotatedDataFrame(
                          data.frame(group = groups, row.names = colnames(mat))))

design <- model.matrix(~ 0 + groups)
colnames(design) <- levels(groups)

contrast <- makeContrasts(
    AvsCtrl = TreatA - Control,
    BvsCtrl = TreatB - Control,
    levels = design
)

fit  <- lmFit(eset, design)
fit2 <- contrasts.fit(fit, contrast)
fit2 <- eBayes(fit2)

saveRDS(fit2, "fit2.rds")
saveRDS(contrast, "contrast.rds")
saveRDS(design, "design.rds")
for (b in c("fit2", "contrast", "design"))
    file.copy(paste0(b, ".rds"), b, overwrite = TRUE)
