# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DMRcate", "minfi")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DMRcate)
library(minfi)

# 1. Reproduce the vignette's data-preparation code
# Since ExperimentHub fetches are forbidden for offline runs, we construct the exact 
# ALLbetas matrix shown in the vignette's `head(ALLbetas)` output.
ALLbetas <- matrix(c(
    0.51221200, 0.8123723, 0.4522275, 0.7993704, 0.2033696, 0.7856451, 0.88279680, 0.8663721, 0.88071230, 0.8594255,
    0.87596630, 0.4896535, 0.8292074, 0.2289017, 0.6004454, 0.9133542, 0.93277520, 0.9023123, 0.89303100, 0.8841929,
    0.88927350, 0.894