# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CGEN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CGEN)

# Reproduce the vignette's data-preparation code for Xdata
data(Xdata, package="CGEN")

# Serialize the Xdata object to the specified input file formats
write.csv(Xdata, "Xdata.csv", row.names = FALSE)
saveRDS(Xdata, "Xdata.csv")
write.table(Xdata, "Xdata.csv", sep = "\t", row.names = FALSE, quote = FALSE)