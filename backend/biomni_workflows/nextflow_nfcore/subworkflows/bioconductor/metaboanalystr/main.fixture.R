# [biomate-fx-deps] fixture generates a tiny synthetic metabolomics dataset for smoke-testing.
# Self-contained: no MetaboAnalystR needed just to WRITE the fixture inputs (base R only), so the
# fixture can be materialized on any clean runtime before the workflow (which does need the pkg).
set.seed(42)

# --- Synthetic peak-intensity table: 60 features x 20 samples (2 groups of 10) ---
n_features <- 60
n_per_grp  <- 10
groups     <- rep(c("Control", "Treatment"), each = n_per_grp)
sample_ids <- paste0(ifelse(groups == "Control", "C", "T"),
                     unlist(lapply(c(n_per_grp, n_per_grp), seq_len)))

feature_ids <- sprintf("M%03d/%s", seq_len(n_features),
                       formatC(round(runif(n_features, 80, 900), 4), format = "f", digits = 4))

# baseline log-normal intensities
mat <- matrix(rlnorm(n_features * length(groups), meanlog = 8, sdlog = 1),
              nrow = n_features, ncol = length(groups))

# inject a real 2-group signal into the first 12 features (up in Treatment)
sig_idx <- 1:12
mat[sig_idx, groups == "Treatment"] <- mat[sig_idx, groups == "Treatment"] * runif(length(sig_idx) * n_per_grp, 2.5, 5.0)

rownames(mat) <- feature_ids
colnames(mat) <- sample_ids

# peak-intensity table: features (rows) x samples (cols)
write.csv(data.frame(Feature = rownames(mat), mat, check.names = FALSE),
          file = "peak_intensity_table.csv", row.names = FALSE, quote = FALSE)

# 2-group class/sample sheet
write.csv(data.frame(Sample = sample_ids, Class = groups),
          file = "class_labels.csv", row.names = FALSE, quote = FALSE)

# optional compound list to exercise the enrichment branch
writeLines(c("Alanine", "Glucose", "Lactic acid", "Citric acid", "Glutamine"),
           "compound_list.txt")
