# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("flowPeaks", "flowCore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(flowPeaks)
library(flowCore)

fcs_file <- system.file("extdata", "0877408774.B08", package="flowCore")

if (file.exists(fcs_file)) {
    file.copy(fcs_file, "0877408774.B08", overwrite = TRUE)
} else {
    # Fallback to another dataset if the specific file is missing
    data(GvHD, package="flowCore")
    write.FCS(GvHD[[1]], "0877408774.B08")
}