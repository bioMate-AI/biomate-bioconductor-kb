# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CHETAH")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CHETAH)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette loads 'headneck_ref' directly from the package's internal datasets.
# Section "4.1 Required data" states: "## load CHETAH's datasets data('headneck_ref')"
data('headneck_ref')

# 'headneck_ref' is now a SingleCellExperiment object in the environment,
# as provided by the CHETAH package.

# 2. Serialize 'headneck_ref' to the declared input file
# The workflow reads 'headneck_ref' using readRDS("headneck_ref").
saveRDS(headneck_ref, file = "headneck_ref.rds")

# Create the 'ribosomal.txt' file.
# The vignette does not provide code to create 'ribosomal.txt'.
# The workflow reads it using read.table("ribosomal.txt", header = FALSE, sep = '\t').
# We will create a dummy file with placeholder ribosomal gene names.
ribosomal_genes <- data.frame(
  gene = c("RPL1", "RPS2", "RPL3", "RPS4", "RPL5"),
  stringsAsFactors = FALSE
)

# Write the dummy ribosomal genes to 'ribosomal.txt'
write.table(ribosomal_genes, file = "ribosomal.txt",
            row.names = FALSE, col.names = FALSE, sep = '\t', quote = FALSE)