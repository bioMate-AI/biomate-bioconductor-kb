# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ACE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ACE)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette uses the 'copyNumbersSegmented' dataset provided within the ace package.
data("copyNumbersSegmented")

# The object created is 'copyNumbersSegmented', which is a QDNAseq object.
# The vignette then often assigns it to 'object' for further use, but the original
# object name is 'copyNumbersSegmented'.

# 2. Serialize that object to EACH declared input file in the EXACT format
# The workflow reads "segmented QDNAseq RDS files".
# The vignette demonstrates saving the QDNAseq object as an RDS file.

# Create a temporary directory for the output file
output_dir <- tempdir()

# Define the full path for the RDS file
rds_filepath <- file.path(output_dir, "copyNumbersSegmented.rds")

# Save the QDNAseq object as an RDS file
saveRDS(copyNumbersSegmented, file = rds_filepath)

# For the "Aligned BAM files in a directory" input type:
# The vignette does not provide code to generate example BAM files from the
# 'copyNumbersSegmented' object or any other data. It only states that users
# would typically start from their own BAM files. Therefore, based on the
# constraint to "reproduce the VIGNETTE'S OWN data-preparation code",
# generating BAM files is not possible with the provided vignette content.
# The script focuses on the 'segmented QDNAseq RDS files' as it's the only
# input type for which data preparation is explicitly shown.

# The script has now created the 'copyNumbersSegmented.rds' file in a temporary directory.
# In a real test fixture scenario, you would typically copy this file to a known
# location or pass its path to the workflow.