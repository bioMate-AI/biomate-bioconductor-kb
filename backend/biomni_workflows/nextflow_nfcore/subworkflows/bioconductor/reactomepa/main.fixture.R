# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ReactomePA", "DOSE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ReactomePA)
library(DOSE)

# Load the example geneList dataset from the DOSE package
data(geneList, package = "DOSE")

# Extract Entrez gene IDs (e.g., genes with absolute fold change > 2)
gene <- names(geneList)[abs(geneList) > 2]

# Write the Entrez gene IDs to the required input file, one per line
writeLines(gene, "gene_list.txt")