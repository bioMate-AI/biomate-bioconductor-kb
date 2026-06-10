# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("benchdamic")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(benchdamic)

# Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette explicitly states:
# "For GOF and TIEC analyses a homogeneous group of samples (...) ps_stool_16S is used"
# "data("ps_stool_16S")"
data("ps_stool_16S")

# Serialize the ps_stool_16S object to the declared input file
# The object is a phyloseq-class experiment-level object (S4),
# so saveRDS is the appropriate serialization method.
saveRDS(ps_stool_16S, file = "ps_stool_16S.rds")