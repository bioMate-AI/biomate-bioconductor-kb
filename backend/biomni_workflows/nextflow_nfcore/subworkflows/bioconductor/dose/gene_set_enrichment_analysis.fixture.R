# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DOSE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DOSE)

# Load the example dataset provided by the DOSE package
data(geneList)

# geneList is a sorted, named numeric vector of fold changes with Entrez gene IDs as names
# We write it to ranked_gene_list.txt as a two-column tab-separated file
write.table(
    data.frame(EntrezID = names(geneList), FoldChange = as.numeric(geneList)),
    file = "ranked_gene_list.txt",
    sep = "\t",
    row.names = FALSE,
    col.names = FALSE,
    quote = FALSE
)