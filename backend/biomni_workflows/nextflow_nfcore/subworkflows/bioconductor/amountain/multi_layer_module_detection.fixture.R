# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AMOUNTAIN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AMOUNTAIN)

# Parameters used in vignette for both single-layer and multi-layer simulations
n = 100
k = 20
theta = 0.5

# --- Data preparation for W (from single-layer network simulation) ---
# As shown in vignette section "3 Module identification for single layer network"
# pp[[1]] is the edge weight matrix W
pp <- networkSimulation(n, k, theta)
W_fixture <- pp[[1]]

# --- Data preparation for listz (from multi-layer network simulation) ---
# As shown in vignette section "5 Module identification for multi-layer network"
# listz is a list of node score vectors for each layer
L = 5 # Number of layers, as used in vignette section 5
cpl <- multilayernetworkSimulation(n, k, theta, L)
listz_fixture <- list()
for (i in 1:L){
  listz_fixture[[i]] <- cpl[[i+2]] # cpl[[i