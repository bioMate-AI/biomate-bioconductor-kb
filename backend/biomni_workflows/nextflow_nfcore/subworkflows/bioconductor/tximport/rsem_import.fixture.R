# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("tximport", "tximportData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(tximport)
library(tximportData)

# Locate the extdata directory from tximportData as done in the vignette
dir <- system.file("extdata", package = "tximportData")
rsem_dir <- file.path(dir, "rsem")

# Find and copy/compress RSEM gene results
rsem_genes <- list.files(rsem_dir, pattern = "\\.genes\\.results", recursive = TRUE, full.names = TRUE)
if (length(rsem_genes) > 0) {
    src <- rsem_genes[1]
    if (grepl("\\.gz$", src)) {
        file.copy(src, "sample.genes.results.gz", overwrite = TRUE)
    } else {
        gz <- gzfile("sample.genes.results.gz", "w")
        writeLines(readLines(src), gz)
        close(gz)
    }
}

# Find and copy/compress RSEM isoform results
rsem_isoforms <- list.files(rsem_dir, pattern = "\\.isoforms\\.results", recursive = TRUE, full.names = TRUE)
if (length(rsem_isoforms) > 0) {
    src <- rsem_isoforms[1]
    if (grepl("\\.gz$", src)) {
        file.copy(src, "sample.isoforms.results.gz", overwrite = TRUE)
    } else {
        gz <- gzfile("sample.isoforms.results.gz", "w")
        writeLines(readLines(src), gz)
        close(gz)
    }
}