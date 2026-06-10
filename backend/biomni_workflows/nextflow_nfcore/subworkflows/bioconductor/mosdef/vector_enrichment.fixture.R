# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("mosdef", "macrophage", "DESeq2", "org.Hs.eg.db", "AnnotationDbi")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library("mosdef")
  library("macrophage")
  library("DESeq2")
  library("org.Hs.eg.db")
  library("AnnotationDbi")
})

data(gse, package = "macrophage")
dds_macrophage <- DESeqDataSet(gse, design = ~ line + condition)
rownames(dds_macrophage) <- substr(rownames(dds_macrophage), 1, 15)

keep <- rowSums(counts(dds_macrophage) >= 10) >= 6
dds_macrophage <- dds_macrophage[keep, ]
dds_macrophage <- DESeq(dds_macrophage)

res_macrophage_IFNg_vs_naive <- results(
  dds_macrophage, 
  contrast = c("condition", "IFNg", "naive"), 
  lfcThreshold = 1, 
  alpha = 0.05
)

res_macrophage_IFNg_vs_naive$symbol <- AnnotationDbi::mapIds(
  org.Hs.eg.db, 
  keys = row.names(res_macrophage_IFNg_vs_naive), 
  column = "SYMBOL", 
  keytype = "ENSEMBL", 
  multiVals = "first" 
)

saveRDS(res_macrophage_IFNg_vs_naive, "res_macrophage_IFNg_vs_naive")