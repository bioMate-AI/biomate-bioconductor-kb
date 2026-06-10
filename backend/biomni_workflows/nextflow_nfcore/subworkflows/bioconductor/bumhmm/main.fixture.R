# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BUMHMM", "Biostrings", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BUMHMM)
library(Biostrings)
library(SummarizedExperiment)

# The 'se' object is provided directly by the BUMHMM package upon loading.
# No explicit data() call is needed.

# Extract the DNA sequence as shown in the vignette
sequence <- subject(rowData(se)$nucl)

# Serialize the objects to .rds files as required by the workflow
saveRDS(se, "se.rds")
saveRDS(sequence, "sequence.rds")