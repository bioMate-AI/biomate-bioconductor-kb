# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TOAST")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TOAST)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette provides several example datasets. We will use the first one,
# "RA_100samples", which explicitly defines Y_raw and Blood_ref.
data("RA_100samples")

# Extract Y_raw from the loaded dataset
Y_raw <- RA_100samples$Y_raw

# Determine K (number of cell types) from the Blood_ref matrix provided
# within the same example dataset. The Blood_ref matrix has 6 columns,
# each representing a distinct cell type.
K <- ncol(RA_100samples$Blood_ref)

# 2. Serialize objects to EACH declared input file in the EXACT format the workflow reads

# Save Y_raw as an RDS file, as per the workflow's reading preference (Y_raw.rds)
saveRDS(Y_raw, "Y_raw.rds")

# Save K as a single integer in a text file, as per the workflow's reading preference (K.txt)
# The workflow reads K.txt using `as.integer(readLines("K.txt", warn = FALSE)[1])`
writeLines(as.character(K), "K.txt")