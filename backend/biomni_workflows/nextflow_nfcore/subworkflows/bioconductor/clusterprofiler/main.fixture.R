# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clusterProfiler", "DOSE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clusterProfiler)
library(DOSE)

# The vignette references DOSE for Disease Ontology and other analyses.
# We use the standard geneList dataset provided by DOSE, which is 
# commonly used in clusterProfiler examples.
data(geneList, package="DOSE")

# Extract a list of gene identifiers (Entrez IDs)
# We select a subset of genes (e.g., those with absolute fold change > 1.5)
gene_ids <- names(geneList)[abs(geneList) > 1.5]

# Write the gene identifiers to the expected input file
writeLines(gene_ids, "gene_list.txt")