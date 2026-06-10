# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("phyloseq", "decontam")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(phyloseq)
library(decontam)

# Load the example phyloseq object from the decontam package as shown in the vignette
ps <- readRDS(system.file("extdata", "MUClite.rds", package="decontam"))

# Extract the otu_table and sample_data S4 objects
otu <- otu_table(ps)
sam <- sample_data(ps)

# Serialize the S4 objects to the declared input files in the working directory
saveRDS(otu, "otu_table")
saveRDS(sam, "sample_data")