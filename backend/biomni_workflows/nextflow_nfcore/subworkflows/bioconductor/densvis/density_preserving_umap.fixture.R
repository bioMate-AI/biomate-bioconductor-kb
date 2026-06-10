# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("densvis", "Rtsne", "uwot", "ggplot2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("densvis")
library("Rtsne")
library("uwot")
library("ggplot2")
theme_set(theme_bw())
set.seed(14)
data <- data.frame(
    x = c(rnorm(1000, 5), rnorm(1000, 0, 0.2)),
    y = c(rnorm(1000, 5), rnorm(1000, 0, 0.2)),
    class = c(rep("Class 1", 1000), rep("Class 2", 1000))
)
write.csv(data[, 1:2], "data.csv", row.names = FALSE)