# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("struct", "ggplot2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(struct)
library(ggplot2)

# Recreate the DatasetExperiment object from the vignette
DE = DatasetExperiment(
    data = iris[, 1:4],
    sample_meta = iris[, 5, drop = FALSE],
    variable_meta = data.frame('idx' = 1:4, row.names = colnames(iris[, 1:4])),
    name = "Fisher's iris dataset",
    description = 'The famous one'
)

# Alternatively, using the built-in formal version
DE_formal = iris_DatasetExperiment()

# Serialize the data to the required input file
write.csv(iris, file = "input.csv", row.names = FALSE)