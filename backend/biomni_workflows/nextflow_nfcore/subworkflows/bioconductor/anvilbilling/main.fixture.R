# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AnVILBilling")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AnVILBilling)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette states: "We took a snapshot of usage in a project we work on, and it is available as demo_rec."
# And later shows: "data (demo_rec) # makes rec"
data(demo_rec)

# 2. Serialize that object to EACH declared input file in the EXACT format the workflow reads.
# The workflow reads:
#   billing_data <- readRDS(input_file)
#   billing_data <- read.csv(input_file, stringsAsFactors = FALSE)
# This implies two possible formats for the "GCP BigQuery billing export table" input.

# The 'demo_rec' object is an S4 object of class 'avReckoning'.
# Its '@reckoning' slot contains the actual tabular data (a tibble).

# Save the full S4 object as an RDS file
saveRDS(demo_rec, file = "gcp_billing_export_table.rds")

# Save the tabular data (tibble from the @reckoning slot) as a CSV file
# Use row.names = FALSE to avoid writing an extra column for row numbers.
write.csv(demo_rec@reckoning, file = "gcp_billing_export_table.csv", row.names = FALSE)