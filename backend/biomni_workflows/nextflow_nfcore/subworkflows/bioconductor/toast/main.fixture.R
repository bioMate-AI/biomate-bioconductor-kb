# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TOAST", "EpiDISH")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TOAST)
library(EpiDISH) # Required for epidish function

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the example dataset RA_100samples
data("RA_100samples")

# Extract Y_raw from the loaded dataset
# This will be serialized to the "Y_raw" input file
Y_raw_input <- RA_100samples$Y_raw

# Extract Pheno (phenotype data) from the loaded dataset
# This will serve as the "design" input file
design_input <- RA_100samples$Pheno

# Calculate mixing proportions (Prop) using the vignette's steps
# Select the top 1000 most variant features from Y_raw_input
refinx <- findRefinx(Y_raw_input, nmarker = 1000)

# Subset the Y_raw_input data and the Blood_ref reference panel using the selected features
Y_subset <- Y_raw_input[refinx,]
Ref_subset <- as.matrix(RA_100samples$Blood_ref[refinx,])

# Use EpiDISH to estimate cellular proportions
outT <- epidish(beta.m = Y_subset, ref.m = Ref_subset, method = "RPC")
Prop_input <- outT$estF

# 2. Serialize the prepared objects to the declared input files
# The workflow's read_input_file function prioritizes readRDS,
# so saveRDS is used for serialization.
saveRDS(Y_raw_input, "Y_raw")
saveRDS(design_input, "design")
saveRDS(Prop_input, "Prop")