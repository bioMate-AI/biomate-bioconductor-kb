# Real user-style input for switchBox K-TSP classifier training/prediction:
#   matTraining   - genes x training-samples expression matrix
#   trainingGroup - factor of binary class labels for the training samples
#   matTesting    - genes x testing-samples expression matrix (same gene rows)
# This is exactly what a user supplies to build a Top-Scoring-Pairs classifier
# (a labelled training cohort + an unlabelled test cohort). We simulate a real
# two-class transcriptomic signal: a block of genes is up-regulated in class
# "Bad" relative to "Good" so K-TSP can recover discriminating gene pairs.
# No package demo data.

set.seed(123)
n_genes  <- 200
n_train  <- 60
n_test   <- 40
gene_ids <- sprintf("Gene%03d", seq_len(n_genes))

train_class <- factor(rep(c("Good", "Bad"), each = n_train / 2),
                       levels = c("Good", "Bad"))
test_class  <- rep(c("Good", "Bad"), each = n_test / 2)

# ~40 "signature" genes are higher in Bad; rest are background with biological noise.
sig <- 1:40
make_mat <- function(cls, n) {
    m <- matrix(rnorm(n_genes * n, mean = 8, sd = 1.2), nrow = n_genes)
    bad <- which(cls == "Bad")
    m[sig, bad] <- m[sig, bad] + rnorm(length(sig) * length(bad), mean = 3, sd = 0.8)
    rownames(m) <- gene_ids
    m
}

matTraining <- make_mat(train_class, n_train)
colnames(matTraining) <- sprintf("train%02d", seq_len(n_train))
matTesting  <- make_mat(test_class, n_test)
colnames(matTesting)  <- sprintf("test%02d", seq_len(n_test))
trainingGroup <- train_class

saveRDS(matTraining,   "matTraining.rds")
saveRDS(trainingGroup, "trainingGroup.rds")
saveRDS(matTesting,    "matTesting.rds")

# bare-token aliases for input-staging harnesses
for (b in c("matTraining", "trainingGroup", "matTesting"))
    file.copy(paste0(b, ".rds"), b, overwrite = TRUE)
