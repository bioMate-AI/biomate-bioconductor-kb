# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("speckle", "SingleCellExperiment", "CellBench", "limma", "ggplot2", "scater", "patchwork", "edgeR", "statmod")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(speckle)
library(SingleCellExperiment)
library(CellBench)
library(limma)
library(ggplot2)
library(scater)
library(patchwork)
library(edgeR)
library(statmod)

# 5 Loading data into R
sc_data <- load_sc_data()

commongenes1 <- rownames(sc_data$sc_dropseq)[rownames(sc_data$sc_dropseq) %in% rownames(sc_data$sc_celseq)]
commongenes2 <- commongenes1[commongenes1 %in% rownames(sc_data$sc_10x)]
sce_10x <- sc_data$sc_10x[