# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("tximport", "tximportData", "readr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(tximport)
library(tximportData)
library(readr)

dir <- system.file("extdata", package = "tximportData")
samples <- read.table(file.path(dir, "samples.txt"), header = TRUE)
files <- file.path(dir, "salmon", samples$run, "quant.sf.gz")

# Copy the first sample's quantification file to the working directory
file.copy(files[1], "quant.sf.gz", overwrite = TRUE)

# Copy the transcript-to-gene mapping file to the working directory
tx2gene_file <- file.path(dir, "tx2gene.gencode.v27.csv")
file.copy(tx2gene_file, "tx2gene.gencode.v27.csv", overwrite = TRUE)