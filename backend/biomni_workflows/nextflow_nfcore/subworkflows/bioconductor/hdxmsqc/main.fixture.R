# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("hdxmsqc")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(hdxmsqc)
})

# Locate the files shipped with the package
file1 <- system.file("extdata", "ELN55049_AllResultsTables_Uncurated.csv", package = "hdxmsqc", mustWork = TRUE)
file2 <- system.file("extdata", "BRD4_RowChecked_20220628_HDsite.csv", package = "hdxmsqc", mustWork = TRUE)
file3 <- system.file("extdata", "BRD4_RowChecked_20220628_HDE.csv", package = "hdxmsqc", mustWork = TRUE)

# Copy them to the working directory to serve as test fixtures
file.copy(file1, "ELN55049_AllResultsTables_Uncurated.csv", overwrite = TRUE)
file.copy(file2, "BRD4_RowChecked_20220628_HDsite.csv", overwrite = TRUE)
file.copy(file3, "BRD4_RowChecked_20220628_HDE.csv", overwrite = TRUE)