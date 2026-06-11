# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MetaboCoreUtils")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MetaboCoreUtils)
src_file <- system.file("txt", "feature_values.txt", package = "MetaboCoreUtils")
if (file.exists(src_file)) {
    file.copy(src_file, "feature_values.txt", overwrite = TRUE)
} else {
    files <- list.files(system.file(package = "MetaboCoreUtils"), pattern = "feature_values\\.txt$", recursive = TRUE, full.names = TRUE)
    if (length(files) > 0) {
        file.copy(files[1], "feature_values.txt", overwrite = TRUE)
    }
}