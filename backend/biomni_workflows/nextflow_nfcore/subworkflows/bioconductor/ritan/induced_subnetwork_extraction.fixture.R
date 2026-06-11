# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RITANdata", "RITAN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RITANdata)
library(RITAN)

my_genes <- c('ABCA2', 'ACAT2', 'ACSS2', 'CD9', 'CPEB2', 'CTNNB1', 'FASN', 'LDLR', 'LPL', 'LSS')
writeLines(my_genes, "my_genes.txt")

sif_data <- data.frame(
    node1 = c("Trp53", "Trp53", "Myc"),
    interaction = c("interacts_with", "interacts_with", "interacts_with"),
    node2 = c("Mdm2", "Brca1", "Max")
)
gz1 <- gzfile("BIOGRID-ORGANISM-Mus_musculus-3.4.136.symbols.sif.gz", "w")
write.table(sif_data, gz1, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
close(gz1)