# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("VanillaICE", "data.table", "foreach")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(VanillaICE)
library(data.table)
library(foreach) # Required by vignette setup, though not directly used for file generation here

# 1. Reproduce the vignette's data-preparation code to materialize the example objects.
#    The vignette's data preparation for the input files (FinalReport*.txt, SNP_info.csv)
#    involves reading them from the package's 'extdata' directory.

# Get the path to the 'extdata' directory of the VanillaICE package
extdir <- system.file("extdata", package="VanillaICE", mustWork=TRUE)

# Identify the SNP_info.csv file in the extdata directory
snp_info_source_path <- file.path