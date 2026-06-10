# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("snifter", "ggplot2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("snifter")
library("ggplot2")
theme_set(theme_bw())
set.seed(42)

n_obs <- 500
n_feats <- 200
means_1 <- rnorm(n_feats)
means_2 <- rnorm(n_feats)
counts_a <- replicate(n_obs, rnorm(n_feats, means_1))
counts_b <- replicate(n_obs, rnorm(n_feats, means_2))
counts <- t(cbind(counts_a, counts_b))
label <- rep(c("A", "B"), each = n_obs)

# Serialize 'counts' object to counts.rds
saveRDS(counts, "counts.csv")

# Serialize 'label' object to labels.txt
writeLines(label, "labels.csv")