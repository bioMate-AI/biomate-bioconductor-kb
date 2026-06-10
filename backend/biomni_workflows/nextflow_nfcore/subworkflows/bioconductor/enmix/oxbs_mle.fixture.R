library(ENmix)

# Generate synthetic data for oxBS-MLE analysis
set.seed(123)
n_probes <- 1000
n_samples <- 6

# Create beta values (methylation proportions)
beta.BS <- matrix(runif(n_probes * n_samples, 0.2, 0.9), nrow = n_probes, ncol = n_samples)
# oxBS beta values are typically lower than or equal to BS beta values
beta.oxBS <- beta.BS * runif(n_probes * n_samples, 0.5, 0.95)

# Create signal intensities / coverage (N values)
N.BS <- matrix(rpois(n_probes * n_samples, 5000), nrow = n_probes, ncol = n_samples)
N.oxBS <- matrix(rpois(n_probes * n_samples, 5000), nrow = n_probes, ncol = n_samples)

# Assign row names (CpG probes) and column names (Samples)
probe_names <- paste0("cg", seq_len(n_probes))
sample_names <- paste0("Sample", seq_len(n_samples))

rownames(beta.BS) <- rownames(beta.oxBS) <- rownames(N.BS) <- rownames(N.oxBS) <- probe_names
colnames(beta.BS) <- colnames(beta.oxBS) <- colnames(N.BS) <- colnames(N.oxBS) <- sample_names

# Serialize the objects to the exact filenames expected by the workflow
saveRDS(beta.BS, "beta.BS")
saveRDS(beta.oxBS, "beta.oxBS")
saveRDS(N.BS, "N.BS")
saveRDS(N.oxBS, "N.oxBS")