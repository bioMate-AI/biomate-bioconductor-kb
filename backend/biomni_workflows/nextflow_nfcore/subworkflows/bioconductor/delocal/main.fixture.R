# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DELocal")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DELocal)

# Reproduce the vignette's data-preparation code to materialize the example objects.
# The vignette reads these files from the package's 'extdata' directory.
# The 'read.table' calls in the vignette do not explicitly specify 'header' or 'sep'.
# However, for typical Bioconductor data, these files are usually tab-separated with headers.
# To ensure the generated files can be read back by the workflow's 'read.table' calls
# (which implicitly handle the format of the 'extdata' files), we first read the
# original files using the vignette's exact calls, and then write them with parameters
# that preserve their structure.

# Read the raw count values as shown in the vignette
# This will create a matrix 'count_matrix' with gene IDs as row names and sample IDs as column names.
count_matrix <- as.matrix(read.table(file = system.file("extdata", "tooth_RNASeq_counts.txt", package = "DELocal")))

# Read the gene location information as shown in the vignette
# This will create a data.frame 'gene_location' with 'ensembl_gene_id' as a regular column.
gene_location <- read.table(file = system.file("extdata", "gene_location.txt", package = "DELocal"))

# Serialize the 'count_matrix' object to 'tooth_RNASeq_counts.txt'.
# To ensure 'read.