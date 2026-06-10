# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("microbiomeMarker", "phyloseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(microbiomeMarker)
library(phyloseq)

# Load example data from microbiomeMarker
data(kostic_crc, package = "microbiomeMarker")

# Subset to keep the files small
ps <- prune_taxa(taxa_names(kostic_crc)[1:100], kostic_crc)
ps <- prune_samples(sample_names(ps)[1:20], ps)

# Extract components
otu <- as(otu_table(ps), "matrix")
sam <- as(sample_data(ps), "data.frame")
tax <- as(tax_table(ps), "matrix")

# Write to required input files
write.csv(otu, file = "otu_table.csv", row.names = TRUE)
write.csv(sam, file = "sample_metadata.csv", row.names = TRUE)
write.csv(tax, file = "taxonomy_table.csv", row.names = TRUE)