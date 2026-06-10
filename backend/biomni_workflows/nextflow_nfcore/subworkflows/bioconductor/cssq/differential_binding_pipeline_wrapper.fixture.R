# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CSSQ")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CSSQ)

# Get the path to the extdata directory within the CSSQ package
extdata_path <- system.file("extdata", package = "CSSQ")

# --- 1. Reproduce chr19_regions.bed ---
# The vignette's data preparation for 'chr19_regions.bed' is to load it from extdata.
# The workflow expects this file in the working directory.
bed_file_name <- "chr19_regions.bed"
bed_src_path <- file.path(extdata_path, bed_file_name)
file.copy(from = bed_src_path, to = bed_file_name, overwrite = TRUE)

# --- 2. Reproduce