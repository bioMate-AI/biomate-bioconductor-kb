# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CBNplot", "bnlearn", "org.Hs.eg.db", "clusterProfiler")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CBNplot)
library(bnlearn)
library(org.Hs.eg.db)
library(clusterProfiler)

## Load data
data(gaussian.test, package = "bnlearn")

## Draw genes in the KEGG pathway as DEG
kegg <- org.Hs.egPATH2EG
mapped <- mappedkeys(kegg)
genes <- as.list(kegg[mapped])[["00532"]]

## Random data
counts <- head(gaussian.test, length(genes))
row.names(counts) <- genes

## Perform enrichment analysis
## Note: Using enrichGO instead of enrichKEGG to guarantee fully offline execution,
## as enrichKEGG requires an active internet connection to query the KEGG API.
pway <- clusterProfiler::enrichGO(
    gene = genes,
    OrgDb = org.Hs.eg.db,
    ont = "BP",
    pvalueCutoff = 1.0,
    qvalueCutoff = 1.0
)
pway <- clusterProfiler::setReadable(pway, org.Hs.eg.db, keyType="ENTREZID")

## Save to the required files
saveRDS(pway, "enrichResult.rds")
write.csv(counts, "expression_matrix.csv", row.names = TRUE)