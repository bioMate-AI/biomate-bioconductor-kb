# Real user-style input for ClassifyR multi-view (multi-omics) integration:
#   measurementsDF.rds - a DataFrame of samples x features spanning TWO assays
#       (e.g. a clinical block + a transcriptomic block), with mcols()$assay
#       tagging which view each feature belongs to (the multi-view contract).
#   classes.rds        - a two-level outcome factor (one label per sample).
# This is exactly the shape a user supplies for multi-omics classification.
# We embed a real class signal in a subset of features of each assay so the SVM
# cross-validation has something to learn. No package demo data.

suppressPackageStartupMessages({
  library(S4Vectors)
})

set.seed(9500)
n_samples <- 80
classes <- factor(rep(c("Healthy", "Disease"), each = n_samples / 2),
                  levels = c("Healthy", "Disease"))

# Assay 1: small clinical block (10 features), a few discriminative
n1 <- 10
a1 <- matrix(rnorm(n_samples * n1), nrow = n_samples)
disease <- which(classes == "Disease")
a1[disease, 1:4] <- a1[disease, 1:4] + 2.0
colnames(a1) <- sprintf("clin_%02d", seq_len(n1))

# Assay 2: larger molecular block (200 features), a marker subset discriminative
n2 <- 200
a2 <- matrix(rnorm(n_samples * n2), nrow = n_samples)
a2[disease, 1:30] <- a2[disease, 1:30] + 1.5
colnames(a2) <- sprintf("gene_%03d", seq_len(n2))

measurements <- cbind(a1, a2)
rownames(measurements) <- sprintf("sample%02d", seq_len(n_samples))

measurementsDF <- DataFrame(measurements, check.names = FALSE)
mcols(measurementsDF) <- DataFrame(
    assay = rep(c("clinical", "molecular"), times = c(n1, n2)),
    feature = colnames(measurementsDF)
)

saveRDS(measurementsDF, "measurementsDF.rds")
saveRDS(classes, "classes.rds")
for (b in c("measurementsDF", "classes"))
    file.copy(paste0(b, ".rds"), b, overwrite = TRUE)
