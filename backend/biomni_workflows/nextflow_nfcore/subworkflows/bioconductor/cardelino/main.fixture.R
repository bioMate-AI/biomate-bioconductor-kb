# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cardelino")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cardelino)

# Define the names of the input files as expected by the workflow
output_vcf_filename <- "cellSNP.cells.vcf.gz"
output_rds_filename <- "canopy_results.coveraged.rds"

# Locate the example data files within the cardelino package's 'extdata' directory
# These are the exact files used in the vignette for data preparation.
vignette_vcf_path <- system.file("extdata", "cellSNP.cells.vcf.gz", package = "cardelino")
vignette_rds_path <- system.file("extdata", "canopy_results.coveraged.rds", package = "cardelino")

# Ensure the vignette files exist before attempting to copy
if (!file.exists(vignette_vcf_path)) {
  stop(paste("Error: Vignette VCF file not found at", vignette_vcf_path))
}
if (!file.exists(vignette_rds_path)) {
  stop(paste("Error: Vignette RDS file not found at", vignette_rds_path))
}

# Copy the VCF file to the current working directory.
# This file will be read by the workflow using `load_cellSNP_vcf`.
file.copy(vignette_vcf_path, output_vcf_filename, overwrite = TRUE)

# Copy the RDS file to the current working directory.
# This file will be read by the workflow using `readRDS`.
file.copy(vignette_rds_path, output_rds_filename, overwrite = TRUE)

# The files 'cellSNP.cells.vcf.gz' and 'canopy_results.coveraged.rds'
# are now available in the working directory, ready for the workflow.