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

# The three single cell experiment objects in sc_data all have differing numbers of genes.
# The first step is to find all the common genes between all three experiments in order to create one large dataset.
commongenes1 <- rownames(sc_data$sc_dropseq)[rownames(sc_data$sc_dropseq) %in% rownames(sc_data$sc_celseq)]
commongenes2 <- commongenes1[commongenes1 %in% rownames(sc_data$sc_10x)]
sce_10x <- sc_data$sc_10x[commongenes2,]
sce_celseq <- sc_data$sc_celseq[commongenes2,]
sce_dropseq <- sc_data$sc_dropseq[commongenes2,]

# 6 Bootstrap additional samples
i.10x <- seq_len(ncol(sce_10x))
i.celseq <- seq_len(ncol(sce_celseq))
i.dropseq <- seq_len(ncol(sce_dropseq))
set.seed(10)
boot.10x <- sample(i.10x, replace=TRUE)
boot.celseq <- sample(i.celseq, replace=TRUE)
boot.dropseq <- sample(i.dropseq, replace=TRUE)
sce_10x_rep2 <- sce_10x[,boot.10x]
sce_celseq_rep2 <- sce_celseq[,boot.celseq]
sce_dropseq_rep2 <- sce_dropseq[,boot.dropseq]

# 7 Combine all SingleCellExperiment objects
sample <- rep(c("S1","S2","S3","S4","S5","S6"), c(ncol(sce_10x),ncol(sce_10x_rep2),ncol(sce_celseq), ncol(sce_celseq_rep2), ncol(sce_dropseq),ncol(sce_dropseq_rep2)))
cluster <- c(sce_10x$cell_line,sce_10x_rep2$cell_line,sce_celseq$cell_line, sce_celseq_rep2$cell_line,sce_dropseq$cell_line, sce_dropseq_rep2$cell_line)
group <- rep(c("10x","celseq","dropseq"), c(2*ncol(sce_10x),2*ncol(sce_celseq),2*ncol(sce_dropseq)))
allcounts <- cbind(counts(sce_10x),counts(sce_10x_rep2), counts(sce_celseq), counts(sce_celseq_rep2), counts(sce_dropseq), counts(sce_dropseq_rep2))
sce_all <- SingleCellExperiment(assays = list(counts = allcounts))
sce_all$sample <- sample
sce_all$group <- group
sce_all$cluster <- cluster

# 8 Visualise the data (these steps modify sce_all, so they should be included to match the vignette's final sce_all state)
sce_all <- scater::logNormCounts(sce_all)
sce_all <- scater::runPCA(sce_all)
sce_all <- scater::runUMAP(sce_all)

# Serialize the sce_all object to sce_all.rds
saveRDS(sce_all, "sce_all.rds")