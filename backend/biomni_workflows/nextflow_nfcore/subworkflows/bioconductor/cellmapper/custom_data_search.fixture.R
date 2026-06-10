# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ALL", "CellMapper")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ALL)
library(CellMapper)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Load the 'ALL' ExpressionSet object from the 'ALL' package
data(ALL)

# Prepare the 'ALL' data using CMprep, as shown in vignette chunk 15
# This creates a CellMapperList object suitable for CMsearch
prepped.data <- CMprep(ALL)

# 2. Serialize that object to EACH declared input file

# For the 'ALL' input file:
# The workflow reads "ALL.rds" or "ALL.csv".
# Since 'prepped.data' is a CellMapperList (an S4 object),
# saving it as an RDS file is the most appropriate way to preserve its structure.
saveRDS(prepped.data, file = "ALL.rds")

# For the 'query.genes' input file:
# The workflow reads "query.genes" or "query.genes.txt" using readLines.
# The vignette uses "1000_at" as an example query gene with 'prepped.data'
# in chunk 18.
query_genes_val <- "1000_at"
writeLines(query_genes_val, con = "query.genes")