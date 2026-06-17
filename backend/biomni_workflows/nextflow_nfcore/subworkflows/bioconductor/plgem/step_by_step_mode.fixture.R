# Real user-style input for PLGEM (step-by-step mode): an ExpressionSet of
# non-negative expression / spectral-count intensities for a two-condition
# experiment with replicates. PLGEM fits a power-law mean-variance model on the
# most-replicated condition, so the data carries a genuine mean-variance
# relationship and a real differential signal. No package demo data.

suppressPackageStartupMessages(library(Biobase))

set.seed(123)
n_features <- 1000
conditions <- c("control", "LPS")
reps <- 4
samples <- paste(rep(conditions, each = reps), seq_len(reps), sep = "_")

base_mu <- 2 ^ runif(n_features, 4, 16)
sim_condition <- function(mu) {
    sapply(seq_len(reps), function(i) mu * 2 ^ rnorm(n_features, 0, 0.35))
}
ctrl <- sim_condition(base_mu)
fc <- rep(1, n_features)
up <- sample(n_features, 60);  fc[up] <- 2 ^ runif(60, 1, 3)
dn <- sample(setdiff(seq_len(n_features), up), 60); fc[dn] <- 2 ^ -runif(60, 1, 3)
lps <- sim_condition(base_mu * fc)

mat <- cbind(ctrl, lps)
mat[mat < 0] <- 0
rownames(mat) <- sprintf("PROT%04d", seq_len(n_features))
colnames(mat) <- samples

pheno <- data.frame(condition = factor(rep(conditions, each = reps), levels = conditions),
                    row.names = samples)
eset <- ExpressionSet(assayData = mat,
                      phenoData = AnnotatedDataFrame(pheno))

saveRDS(eset, "ExpressionSet.rds")
file.copy("ExpressionSet.rds", "ExpressionSet", overwrite = TRUE)
