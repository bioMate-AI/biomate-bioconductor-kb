# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AMOUNTAIN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AMOUNTAIN)

# Reproduce the vignette's data-preparation code for two-layer network simulation
# This code is found under "2 Network simulation" in the vignette,
# specifically the section "When simulating a two-layer network".
n1 = 100
k1 = 20
theta1 = 0.5
n2 = 80
k2 = 10
theta2 = 0.5
ppresult <- twolayernetworkSimulation(n1,k1,theta1,n2,k2,theta2)

# Extract the required objects based on the workflow's input names and the vignette's structure.
# The workflow reads W1, z1, W2, z2, A.
# From the vignette's usage of moduleIdentificationGPFixSSTwolayer(pp[[1]],pp[[2]],...,pp2[[1]],pp2[[2]],...,A),
# and the assignment A <- ppresult[[3]], we can deduce the mapping.

# A is directly assigned in the vignette
A <- ppresult[[3]]

# pp is the first element of ppresult
pp <- ppresult[[1]]
# W1 is the first element of pp (the edge weight matrix for layer 1)
W1 <- pp[[1]]
# z1 is the second element of pp (the node score vector for layer 1)
z1 <- pp[[2]]

# pp2 is the second element of ppresult
pp2 <- ppresult[[2]]
# W2 is the first element of pp2 (the edge weight matrix for layer 2)
W2 <- pp2[[1]]
# z2 is the second element of pp2 (the node score vector for layer 2)
z2 <- pp2[[2]]

# Serialize these objects to CSV files without headers.
# The workflow's read_input function uses read.csv(filepath, header = FALSE)
# or read.table(filepath, header = FALSE), implying comma-separated values
# without row or column names.
write.csv(W1, "W1.csv", row.names = FALSE, col.names = FALSE)
write.csv(z1, "z1.csv", row.names = FALSE, col.names = FALSE)
write.csv(W2, "W2.csv", row.names = FALSE, col.names = FALSE)
write.csv(z2, "z2.csv", row.names = FALSE, col.names = FALSE)
write.csv(A, "A.csv", row.names = FALSE, col.names = FALSE)