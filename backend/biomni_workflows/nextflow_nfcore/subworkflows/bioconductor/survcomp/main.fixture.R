# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("survcomp", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(survcomp)
library(Biobase)

data(breastCancerData)

saveRDS(mainz7g, "mainz7g.rds")
saveRDS(transbig7g, "transbig7g.rds")
saveRDS(upp7g, "upp7g.rds")
saveRDS(unt7g, "unt7g.rds")
saveRDS(vdx7g, "vdx7g.rds")
saveRDS(nki7g, "nki7g.rds")