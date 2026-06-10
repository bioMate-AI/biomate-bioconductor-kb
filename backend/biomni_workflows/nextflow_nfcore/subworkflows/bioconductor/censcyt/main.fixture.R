# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("censcyt", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library(censcyt)
  library(SummarizedExperiment)
})

# Reproduce data preparation from vignette
set.seed(1234)
nr_samples <- 50
nr_clusters <- 6

# Simulate censored covariate
X_true <- rexp(nr_samples)
C <- rexp(nr_samples)
X_obs <- pmin(X_true,C)
Event_ind <- ifelse(X_true>C,0,1)

# Simulate cell counts
sizes <- round(runif(nr_samples,1e3,1e4))
alphas <- runif(nr_clusters,1,10)

simulation_output <- simulate_multicluster(alphas = alphas, sizes = sizes, covariate = X_obs, nr_diff = 2, return_summarized_experiment = TRUE, slope = list(0.9))
d_counts <- simulation_output$counts

# Set up meta-data
experiment_info <- data.frame(sample_id = seq_len(nr_samples), X_obs = X_obs, Event_ind = Event_ind)

# Serialize objects to files
saveRDS(d_counts, "d_counts.rds")
write.csv(experiment_info, "experiment_info.csv", row.names = FALSE)
saveRDS(experiment_info, "experiment_info.csv")