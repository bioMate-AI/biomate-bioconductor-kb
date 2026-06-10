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

# 1. Prepare and write tx2gene.gencode.v27.csv
tx2gene_path <- file.path(dir, "tx2gene.gencode.v27.csv")
if (file.exists(tx2gene_path)) {
    tx2gene <- read_csv(tx2gene_path, show_col_types = FALSE)
    write_csv(tx2gene, "tx2gene.gencode.v27.csv")
}

# 2. Prepare and write quant.sf.gz
samples_path <- file.path(dir, "samples.txt")
if (file.exists(samples_path)) {
    samples <- read.table(samples_path, header = TRUE)
    # Use the first sample's salmon quantification file as the representative quant.sf.gz
    quant_path <- file.path(dir, "salmon", samples$run[1], "quant.sf.gz")
    if (file.exists(quant_path)) {
        file.copy(quant_path, "quant.sf.gz", overwrite = TRUE)
    }
}