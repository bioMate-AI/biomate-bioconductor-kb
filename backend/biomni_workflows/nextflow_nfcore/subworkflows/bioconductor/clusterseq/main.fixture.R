# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clusterSeq", "baySeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clusterSeq)
library(baySeq) # Required for getLibsizes

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load ratThymus dataset
data(ratThymus, package = "clusterSeq")

# Define replicates vector
replicates <- c("2week","2week","2week","2week",
                "6week","6week","6week","6week",
                "21week","21week","21week","21week",
                "104week","104week","104week","104week")

# Calculate libsizes using the original ratThymus
libsizes <- getLibsizes(data = ratThymus)

# 2. Serialize objects to declared input files in the exact format the workflow reads

# Save ratThymus (matrix)
saveRDS(ratThymus, "ratThymus.rds")

# Save libsizes (numeric vector)
saveRDS(libsizes, "libsizes.rds")

# Save replicates (character vector)
saveRDS(replicates, "replicates.rds")