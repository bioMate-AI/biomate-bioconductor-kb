# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("censcyt", "ggplot2", "SummarizedExperiment", "tidyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library(censcyt)
  library(ggplot2)
  library(SummarizedExperiment)
  library(tidyr)
})

# Set seed for reproducibility as in the vignette
set.seed(1234)

# --- Data generation for experiment_info and d_input ---
nr_samples <- 50
# The covariate is simulated from an exponential distribution:
X_true <- rexp(nr_samples)
# The censoring time is also sampled from an exponential distribution:
C <- rexp(nr_samples)
# The actual observed value is the minimum of the two:
X_obs <- pmin(X_true, C)
# Additionally, we have the event indicator:
Event_ind <- ifelse(X_true > C, 0, 1)

# --- Create experiment_info ---
experiment_info <- data.frame(
  sample_id = seq_len(nr_samples),
  X_obs = X_obs,
  Event_ind = Event_ind,
  stringsAsFactors = FALSE
)

# --- Define functions for d_input generation ---
# Function to create expression data (one sample)
fcs_sim <- function(n = 2000, mean = 0, sd = 1, ncol = 10, cof = 5) {
  d <- matrix(sinh(rnorm(n * ncol, mean, sd)) * cof, ncol = ncol)
  # each marker is heavily expressed in one population, i.e. this should result
  # in 'ncol' clusters
  for (i in seq_len(ncol)) {
    d[seq(n / ncol * (i - 1) + 1, n / ncol * (i)), i] <- sinh(rnorm(n / ncol, mean + 2, sd)) * cof
  }
  colnames(d) <- paste0("marker", sprintf("%02d", 1:ncol))
  d
}

# Create multiple expression data samples with DA signal
comb_sim <- function(X, nr_samples = 10, mean = 0, sd = 1, ncol = 10, cof = 5) {
  # Create random data (without differential signal)
  d_input <- lapply(seq_len(nr_samples), function(i) fcs_sim(mean = mean, sd = sd, ncol = ncol, cof = cof))
  # Add differential abundance (DA) signal
  for (i in seq_len(nr_samples)) {
    # number of cells in cluster 1
    n_da <- round((plogis(X_true[i])) * 300) # Note: uses X_true from global scope as in vignette
    # set to random expression
    d_input[[i]][seq_len(n_da), ] <- matrix(sinh(rnorm(n_da * ncol, mean, sd)) * cof, ncol = ncol)
    # increase expression for cluster 1
    d_input[[i]][seq_len(n_da), 1] <- sinh(rnorm(n_da, mean + 2, sd)) * cof
  }
  d_input
}

# --- Create d_input ---
d_input <- comb_sim(X_true, nr_samples = 50)

# --- Create marker_info ---
marker_info <- data.frame(
  channel_name = paste0("channel", sprintf("%03d", seq_len(10))),
  marker_name = paste0("marker", sprintf("%02d", seq_len(10))),
  marker_class = factor(c(rep("type", 10)), levels = c("type", "state", "none")),
  stringsAsFactors = FALSE
)

# --- Serialize objects to files ---
write.csv(experiment_info, "experiment_info.csv", row.names = FALSE)
write.csv(marker_info, "marker_info.csv", row.names = FALSE)
saveRDS(d_input, "d_input.rds")