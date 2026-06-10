# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DESeq2", "airway")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DESeq2)
library(airway)

# Load the airway dataset shipped with the airway package
data(airway, package="airway")

# Extract the count matrix and sample metadata
cts <- assay(airway)
coldata <- as.data.frame(colData(airway))

# The vignette's quick start expects 'batch' and 'condition' columns in coldata
coldata$condition <- coldata$dex
coldata$batch <- coldata$cell

# Serialize to the declared input files
saveRDS(cts, "cts")
saveRDS(coldata, "coldata")