# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BayesKnockdown")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BayesKnockdown)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Using the "Simulated Data Example" from chunk 1 of the vignette.
set.seed(1618)
n <- 100 # Number of observations (columns in y, length of x)
p <- 10  # Number of target genes (rows in y)

x <- rnorm(n) # Predictor vector
y <- matrix(nrow = p, data = rnorm(n * p)) # Targets matrix
y[3,] <- y[3,] + 0.5 * x # Introduce a relationship for target gene 3

# Add explicit names to the 'y' matrix