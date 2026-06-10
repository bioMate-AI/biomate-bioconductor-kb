# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DEGraph", "KEGGgraph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DEGraph)
library(KEGGgraph)

data("Loi2008_DEGraphVignette", package="DEGraph")

classData <- classLoi2008
exprData <- exprLoi2008
annData <- annLoi2008
grList <- grListKEGG

saveRDS(exprData, "exprData.rds")
saveRDS(classData, "classData.rds")
saveRDS(grList, "grList.rds")
saveRDS(annData, "annData.rds")