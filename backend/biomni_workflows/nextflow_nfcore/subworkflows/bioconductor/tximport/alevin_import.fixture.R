# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("tximportData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(tximportData)

dir <- system.file("extdata", package = "tximportData")
alevin_files <- list.files(dir, pattern = "quants_mat\\.gz$", recursive = TRUE, full.names = TRUE)

if (length(alevin_files) > 0 && file.exists(alevin_files[1])) {
    file.copy(alevin_files[1], "quants_mat.gz", overwrite = TRUE)
} else {
    stop("quants_mat.gz not found in tximportData")
}