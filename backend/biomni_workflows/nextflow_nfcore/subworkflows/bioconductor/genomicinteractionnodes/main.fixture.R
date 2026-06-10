# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GenomicInteractionNodes")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GenomicInteractionNodes)

# Locate the shipped example file
p <- system.file("extdata", "WT.2.bedpe", package = "GenomicInteractionNodes")

# Copy it to the working directory so the workflow can read it
if (file.exists(p)) {
    file.copy(p, "WT.2.bedpe", overwrite = TRUE)
} else {
    stop("The required file WT.2.bedpe was not found in the package extdata.")
}