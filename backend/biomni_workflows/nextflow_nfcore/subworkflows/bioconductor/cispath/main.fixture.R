# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cisPath")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cisPath)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
#    Since the vignette is empty, we use the package's documented example data.
data(example_protein_list)
data(example_ppi)

# 2. Serialize the objects to EACH declared input file
#    protein_list.txt: A plain text file with one protein identifier per line.
writeLines(example_protein_list, "protein_list.txt")

#    ppi_data.tsv: A tab-separated file for protein-protein interactions.
#    The example_ppi data frame has columns suitable for this.
write.table(example_ppi, "ppi_data.tsv", sep = "\t", row.names = FALSE, quote = FALSE)