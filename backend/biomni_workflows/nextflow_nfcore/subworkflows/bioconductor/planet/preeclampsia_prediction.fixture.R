# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("planet")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(planet)

# Load the example dataset provided by the planet package
data("plBetas", package = "planet")

# The vignette notes for predictPreeclampsia: "samples must be rows and CpGs must be columns"
# plBetas has CpGs as rows and samples as columns (13918 x 24), so we transpose it.
DNAm_betas_normalized <- t(plBetas)

# Save to the expected input file
saveRDS(DNAm_betas_normalized, "DNAm_betas_normalized.rds")