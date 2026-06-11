# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ExperimentHub")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("ExperimentHub")

# Define output file names as used by the workflow
query_file <- "query"
dataset_file <- "BrainAtlas.rds"

# --- Data preparation from vignette ---

# Reproduce the BrainAtlas object (CellMapperData object)
hub <- ExperimentHub()
# The vignette shows `x <- query(hub, "CellMapperData")` then `BrainAtlas <- hub[["EH170"]]`.
# We directly get EH170 as it's the specific dataset used.
BrainAtlas <- hub[["EH170"]]

# Reproduce the query object
query <- "2571"

# --- Serialization to workflow input files ---

# Save the BrainAtlas object as an RDS file
saveRDS(BrainAtlas, file = dataset_file)

# Save the query string to a plain text file
writeLines(query, con = query_file)