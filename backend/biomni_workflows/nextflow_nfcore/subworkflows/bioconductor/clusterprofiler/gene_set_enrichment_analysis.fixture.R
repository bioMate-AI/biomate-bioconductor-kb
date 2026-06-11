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

# Load the standard example dataset provided by DOSE (a dependency of clusterProfiler)
data(geneList, package="DOSE")

# geneList is a named numeric vector of fold changes, sorted in decreasing order.
# We convert it to a data frame to write out as a text file.
ranked_genes_df <- data.frame(
  Gene = names(geneList),
  Score = as.numeric(geneList),
  stringsAsFactors = FALSE
)

# Write to the expected input file
write.table(
  ranked_genes_df, 
  file = "ranked_gene_list.txt", 
  sep = "\t", 
  quote = FALSE, 
  row.names = FALSE, 
  col.names = TRUE
)