# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CEMiTool")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("CEMiTool")

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load expression data
data(expr0)

# Load sample annotation data
data(sample_annot)

# Get the path to the example GMT file
gmt_fname_source <- system.file("extdata", "pathways.gmt", package = "CEMiTool")

# Get the path to the example interactions file
int_fname_source <- system.file("extdata", "interactions.tsv", package = "CEMiTool")

# 2. Serialize objects to declared input files in the exact format the workflow reads

# Write expression data to expression_data.csv
# The workflow reads with `row.names = 1`, so write row names.
# Use `quote = FALSE` to match typical data file generation for workflows.
write.csv(expr0, "expression_data.csv", row.names = TRUE, quote = FALSE)

# Write sample annotation to sample_annotation.csv
# The workflow reads without `row.names`, so do not write row names.
# Use `quote = FALSE` to match typical data file generation for workflows.
write.csv(sample_annot, "sample_annotation.csv", row.names = FALSE, quote = FALSE)

# Copy the GMT file directly from the package's extdata
file.copy(gmt_fname_source, "pathways.gmt", overwrite = TRUE)

# Copy the interactions TSV file directly from the package's extdata
file.copy(int_fname_source, "interactions.tsv", overwrite = TRUE)