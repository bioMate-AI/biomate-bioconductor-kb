# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("signatureSearch")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(signatureSearch)

# Create a small synthetic reference database as described in the vignette
# using the build_custom_db function to avoid online ExperimentHub fetches.
mat <- matrix(rnorm(1000), nrow = 100, ncol = 10)
rownames(mat) <- as.character(1:100)
colnames(mat) <- paste0("drug", 1:10)

# Build the custom HDF5 reference database
build_custom_db(as.data.frame(mat), "refdb")

# Create batch_queries: a list of query signatures containing upset and downset gene lists
batch_queries <- list(
  query1 = list(upset = as.character(1:5), downset = as.character(6:10)),
  query2 = list(upset = as.character(11:15), downset = as.character(16:20))
)

# Serialize batch_queries to RDS
saveRDS(batch_queries, "batch_queries.rds")