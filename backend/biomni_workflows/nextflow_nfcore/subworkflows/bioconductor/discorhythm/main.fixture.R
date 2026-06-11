# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DiscoRhythm")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DiscoRhythm)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette (Section 3.2) states: "This software package contains truncated transcriptomic datasets
# that can be exported from R for use with DiscoRhythm, including a simulated dataset
# (object name cycSimu4h2d) containing various waveforms to test the performance of the rhythm
# detection algorithms."
# We load this object using `data()`.
data(cycSimu4h2d)

# 2. Prepare the object for serialization to `temporal_data.csv`
# The workflow reads `temporal_data.csv` using `read.csv("temporal_data.csv", check.names = FALSE)`.
# The vignette (Section 4.1, 4.2) describes the input format:
# - The first column should contain unique feature IDs (e.g., gene names), with the header "IDs