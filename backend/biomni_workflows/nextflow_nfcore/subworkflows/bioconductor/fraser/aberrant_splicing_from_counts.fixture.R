# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("FRASER")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(FRASER)

# The required input files are shipped with the FRASER package in the extdata directory.
# We copy them to the working directory to serve as test fixtures for the workflow.

sample_table_path <- system.file("extdata", "sampleTable_countTable.tsv", package="FRASER", mustWork=TRUE)
junction_counts_path <- system.file("extdata", "raw_junction_counts.tsv.gz", package="FRASER", mustWork=TRUE)
site_counts_path <- system.file("extdata", "raw_site_counts.tsv.gz", package="FRASER", mustWork=TRUE)

file.copy(sample_table_path, "sampleTable_countTable.tsv", overwrite = TRUE)
file.copy(junction_counts_path, "raw_junction_counts.tsv.gz", overwrite = TRUE)
file.copy(site_counts_path, "raw_site_counts.tsv.gz", overwrite = TRUE)