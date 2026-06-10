# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DOSE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DOSE)

# Load the built-in dataset from DOSE
data(geneList, package="DOSE")

# Extract a subset of Entrez gene IDs (names of the geneList vector)
# We select genes with absolute fold change > 1.5 as a typical gene list
genes <- names(geneList)[abs(geneList) > 1.5]

# Write the Entrez gene IDs to the expected input file
writeLines(genes, "gene_list.txt")