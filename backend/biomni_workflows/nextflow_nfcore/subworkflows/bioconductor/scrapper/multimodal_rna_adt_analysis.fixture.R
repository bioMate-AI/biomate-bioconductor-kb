# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scrapper", "scRNAseq", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scrapper)
library(scRNAseq)
library(SingleCellExperiment)

sce.s <- StoeckiusHashingData(mode=c("human", "adt1", "adt2"))
sce.s <- sce.s[, 1:5000]

# Combining the various ADT-related alternative experiments into a single object.
altExp(sce.s, "all.adts") <- rbind(altExp(sce.s, "adt1"), altExp(sce.s, "adt2"))
altExp(sce.s, "adt1") <- altExp(sce.s, "adt2") <- NULL

saveRDS(sce.s, "sce.s")