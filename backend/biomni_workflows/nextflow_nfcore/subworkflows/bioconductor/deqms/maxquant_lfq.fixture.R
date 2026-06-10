# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("matrixStats")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(matrixStats) # Required for rowMins

# This script generates a synthetic 'proteinGroups.txt' file and then
# applies the data preparation steps from the deqms vignette (Section 2.2).
# Synthetic data is used because the vignette's original data acquisition
# method (download.file) is forbidden by the "run fully OFFLINE" constraint,
# and the deqms package does not provide example data via system.file or data().

# --- Synthetic Data Generation for proteinGroups.txt ---
num_proteins <- 10 # Number of proteins
num_samples <- 6   # Number of samples (e.g., 3 H, 3 L)

# Create a data frame with at least 94 columns to match vignette's indexing (19:24 and 89:94)
df.prot_synthetic <- as.data.frame(matrix(NA, nrow = num_proteins, ncol = 94))

# Assign specific columns and their names as used in the vignette
# Column 1: Majority.protein.IDs
df.prot_synthetic[, 1] <- paste0("Protein_", 1:num_proteins)
colnames(df.prot_synthetic)[1] <- "Majority.protein.IDs"

# Column 2: Reverse (used for filtering, e.g., one decoy protein)
df.prot_synthetic[, 2] <- c(rep("", num_proteins - 1), "+")
colnames