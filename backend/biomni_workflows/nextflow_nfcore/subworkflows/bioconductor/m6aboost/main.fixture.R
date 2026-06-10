# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("m6Aboost")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(m6Aboost)

testpath <- system.file("extdata", package = "m6Aboost")

# Copy the shipped test data to the required input filenames in the working directory
file.copy(file.path(testpath, "test.rds"), "peak_calling_results.rds", overwrite = TRUE)
file.copy(file.path(testpath, "truncation_positive.bw"), "truncation_positive.bw", overwrite = TRUE)
file.copy(file.path(testpath, "truncation_negative.bw"), "truncation_negative.bw", overwrite = TRUE)
file.copy(file.path(testpath, "C2T_positive.bw"), "C2T_positive.bw", overwrite = TRUE)
file.copy(file.path(testpath, "C2T_negative.bw"), "C2T_negative.bw", overwrite = TRUE)
file.copy(file.path(testpath, "test_annotation.gff3"), "annotation.gff3", overwrite = TRUE)