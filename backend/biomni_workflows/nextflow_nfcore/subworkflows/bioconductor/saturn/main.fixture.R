# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("satuRn")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(satuRn)

# Load the example data objects provided by the satuRn package
# These are the exact objects the vignette uses as its starting point
data(Tasic_counts_vignette)
data(Tasic_metadata_vignette)

# Serialize the objects to files in the working directory.
# The workflow's `load_input` function attempts to read RDS files first.
# `Tasic_counts_vignette` is a matrix, `Tasic_metadata_vignette` is a data.frame.
# `saveRDS` is suitable for both to preserve their R object structure.
saveRDS(Tasic_counts_vignette, "Tasic_counts_vignette")
saveRDS(Tasic_metadata_vignette, "Tasic_metadata_vignette")