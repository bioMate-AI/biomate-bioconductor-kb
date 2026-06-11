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

# 1. Transcript-to-gene mapping file
tx2gene_path <- file.path(dir, "tx2gene.gencode.v27.csv")
if (file.exists(tx2gene_path)) {
    file.copy(tx2gene_path, "tx2gene.gencode.v27.csv", overwrite = TRUE)
}

# 2. Salmon quantification file
samples <- read.table(file.path(dir, "samples.txt"), header = TRUE)
salmon_file <- file.path(dir, "salmon", samples$run[1], "quant.sf.gz")
if (file.exists(salmon_file)) {
    file.copy(salmon_file, "quant.sf.gz", overwrite = TRUE)
}