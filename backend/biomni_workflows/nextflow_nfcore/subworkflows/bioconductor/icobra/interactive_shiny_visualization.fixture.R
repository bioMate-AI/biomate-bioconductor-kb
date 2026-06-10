# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("iCOBRA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(iCOBRA)

# Load the example data provided with the package
data(cobradata_example)

# Calculate adjusted p-values as done in the vignette
cobradata_example <- calculate_adjp(cobradata_example)

# Serialize the COBRAData object to an RDS file
saveRDS(cobradata_example, "cobradata_example.rds")

# Generate the text files containing truth and results
COBRAData_to_text(
  cobradata = cobradata_example,
  truth_file = "cobradata_truth.txt",
  result_files = "cobradata_results.txt",
  feature_id = "feature"
)