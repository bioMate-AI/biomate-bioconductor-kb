# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BASiCS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BASiCS)

# Load the built-in MCMC chain from the package as referenced in the vignette
data(ChainSC)

# Create objects with generic names that might be expected by the workflow
Chain <- ChainSC
Chain1 <- ChainSC

# Save to chain1.RData
save(Chain, Chain1, ChainSC, file = "chain1.RData")

# Try to load ChainRNA for the second group if it exists, otherwise reuse ChainSC
Chain2 <- ChainSC
try({
    data(ChainRNA)
    Chain2 <- ChainRNA
}, silent = TRUE)

# Save to chain2.RData
save(Chain, Chain2, file = "chain2.RData")