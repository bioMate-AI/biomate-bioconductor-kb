# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("gpls")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(gpls)

set.seed(123)

## training set
x <- matrix(rnorm(20), ncol=2)
y <- sample(0:1, 10, TRUE)

## test set
x1 <- matrix(rnorm(10), ncol=2)
y1 <- sample(0:1, 5, TRUE)

saveRDS(x, "x.csv")
saveRDS(y, "y.csv")
saveRDS(x1, "x1.csv")
saveRDS(y1, "y1.csv")