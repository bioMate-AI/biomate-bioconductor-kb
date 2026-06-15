# Real user-style input for wpm (Well-Plate Maker): an eSet (ExpressionSet /
# MSnSet) describing the samples to lay out on a microplate, with phenoData whose
# first column is the experimental GROUP each sample belongs to. wpm's
# convertESet() + wrapperWPM() use this grouping to randomise samples across
# wells while balancing groups. We build a genuine multi-group sample sheet (the
# shape a proteomics/expression user supplies); an ExpressionSet is accepted by
# wpm exactly like an MSnSet and avoids a hard MSnbase dependency. No demo data.

suppressPackageStartupMessages(library(Biobase))

set.seed(123)
groups <- rep(c("Control", "TreatA", "TreatB"), each = 10)   # 30 samples, 3 groups
n_samples <- length(groups)
n_features <- 50

exprs_mat <- matrix(rnorm(n_features * n_samples, mean = 20, sd = 4),
                    nrow = n_features, ncol = n_samples)
sample_ids <- sprintf("S%02d", seq_len(n_samples))
colnames(exprs_mat) <- sample_ids
rownames(exprs_mat) <- sprintf("prot%02d", seq_len(n_features))

pdata <- data.frame(Group = factor(groups), row.names = sample_ids)

my_MSnSet_object <- ExpressionSet(
    assayData = exprs_mat,
    phenoData = AnnotatedDataFrame(pdata)
)

saveRDS(my_MSnSet_object, "my_MSnSet_object.rds")
file.copy("my_MSnSet_object.rds", "my_MSnSet_object", overwrite = TRUE)
