# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("mvtnorm")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(mvtnorm)

# --- Reproduce vignette data preparation (Chunk 3) ---

# Define sigma matrix
sigma <- matrix(c(4,2,0.5,0.5,2,3,0.5,0.5,0.5,0.5,3,2.5,0.5,0.5,2.5,4), ncol=4)

# Simulate data
# The vignette uses n=500 for rmvnorm and then passes n=500 to EBsingle.
# This 'n' is the number of samples used to calculate the covariance matrix.
n_samples <- 500
x <- rmvnorm(n=n_samples, mean=c(1,2,1.5,2.5), sigma=sigma)

# Calculate sample covariance matrix
samplecov <- cov(x)

# Add row and column names
vnames <- paste("a",1:4,sep="")
rownames(samplecov) <- vnames
colnames(samplecov) <- vnames

# Define groups
groups <- list(c("a1","a2"),c("a3","a4"))

# Define n (number of samples used to calculate the covariance matrix)
# This 'n' is explicitly passed to EBsingle in the vignette and read from 'n.txt' in the workflow.
n <- n_samples

# --- Serialize objects to files ---

# Save samplecov
# Workflow reads samplecov.rds or samplecov.csv. saveRDS is preferred for R objects.
saveRDS(samplecov, "samplecov.rds")

# Save groups
# Workflow reads groups.rds, groups.json, or groups.txt. saveRDS is preferred for R list.
saveRDS(groups, "groups.rds")

# Save n
# Workflow reads n.txt or n.
writeLines(as.character(n), "n.txt")