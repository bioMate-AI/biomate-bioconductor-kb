# Real user-style input for PLGEM: an ExpressionSet of (non-negative) expression
# / spectral-count intensities for a two-condition experiment with replicates --
# exactly what a user supplies (e.g. a label-free proteomics quantification table
# with a control vs. treatment design). PLGEM fits a power-law mean-variance model
# on the replicated condition, so the data must have several replicates per
# condition and a real mean-variance relationship. No package demo data.

suppressPackageStartupMessages(library(Biobase))

set.seed(123)
n_features <- 1000
conditions <- c("control", "LPS")
reps <- 4
samples <- paste(rep(conditions, each = reps), seq_len(reps), sep = "_")

# Baseline per-protein abundance spanning several orders of magnitude.
base_mu <- 2 ^ runif(n_features, 4, 16)

sim_condition <- function(mu) {
    # multiplicative (log-normal) noise -> realistic power-law mean/variance
    sapply(seq_len(reps), function(i) mu * 2 ^ rnorm(n_features, 0, 0.35))
}
ctrl <- sim_condition(base_mu)
# ~12% of proteins up- or down-regulated under LPS
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

saveRDS(eset, "expression_set.rds")
file.copy("expression_set.rds", "expression_set", overwrite = TRUE)
