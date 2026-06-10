# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("microbiome", "phyloseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(microbiome)
library(phyloseq)

# Load example data from the microbiome package
data(dietswap, package = "microbiome")

# Extract the abundance table (OTU table)
# taxa are rows, samples are columns
abund <- as.data.frame(otu_table(dietswap))

# Extract the sample metadata (coldata)
coldata <- as(sample_data(dietswap), "data.frame")

# Write the extracted data to the required input files
write.csv(abund, file = "abundance.csv", quote = FALSE)
write.csv(coldata, file = "coldata.csv", quote = FALSE)