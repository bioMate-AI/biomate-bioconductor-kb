# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Biobase", "colonCA", "clustComp")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Biobase)
library(colonCA)
data(colonCA)

rownames(colonCA)[39:42] <- paste("HSAC07", 0:3)
rownames(colonCA)[50:53] <- paste("UMGAP", 0:3)
rownames(colonCA)[260:263] <- paste("i", 0:3)

library(clustComp)

set.seed(0)
flat1 <- paste("A", kmeans(exprs(colonCA), 7)$cluster, sep = "")
flat2 <- paste("B", kmeans(exprs(colonCA), 6)$cluster, sep = "")

saveRDS(flat1, "flat1.rds")
saveRDS(flat2, "flat2.rds")