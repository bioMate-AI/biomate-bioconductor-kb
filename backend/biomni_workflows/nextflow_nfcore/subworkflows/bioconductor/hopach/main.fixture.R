# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("hopach")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(hopach)

# Reproduce data preparation from vignette
data(golub)
vars <- apply(golub, 1, var)
subset <- vars > quantile(vars, (nrow(golub) - 200) / nrow(golub))
golub.subset <- golub[subset,]
gnames.subset <- golub.gnames[subset,]

# Serialize objects to files in the working directory
saveRDS(golub.subset, "golub.subset")
saveRDS(gnames.subset, "gnames.subset")