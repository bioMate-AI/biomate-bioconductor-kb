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

# Load the example phyloseq object from the decontam package
ps <- readRDS(system.file("extdata", "MUClite.rds", package="decontam"))

# Extract the OTU table (feature table of sequence abundances)
otu <- as(otu_table(ps), "matrix")

# Extract the sample data (metadata containing DNA concentration measurements)
sam <- as(sample_data(ps), "data.frame")

# Serialize to the declared input files in the working directory
write.csv(otu, file = "otu_table", quote = FALSE)
write.csv(sam, file = "sample_data", quote = FALSE)