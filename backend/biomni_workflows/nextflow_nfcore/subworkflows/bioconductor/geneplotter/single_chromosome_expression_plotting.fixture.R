# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("geneplotter", "Biobase", "annotate", "hgu95av2.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(geneplotter)
library(Biobase)
library(annotate)
library(hgu95av2.db)

# 1. sample.ExpressionSet
data(sample.ExpressionSet, package = "Biobase")
saveRDS(sample.ExpressionSet, "sample.ExpressionSet")

# 2. chrObj
chrObj <- buildChromLocation("hgu95av2")
saveRDS(chrObj, "chrObj")