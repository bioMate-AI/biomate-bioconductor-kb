# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("singscore", "GSEABase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(singscore)
library(GSEABase)

# Rank the example gene expression dataset
rankData <- rankGenes(tgfb_expr_10_se)

# Score the samples against the example TGFb gene signature
scoredf <- simpleScore(rankData, upSet = tgfb_gs_up, downSet = tgfb_gs_dn)

# Serialize the resulting data frame to the required input files
# Using saveRDS as the input spec defines them as "Data frame" objects without file extensions
saveRDS(scoredf, "scoredf_ccle_epi")
saveRDS(scoredf, "scoredf_ccle_mes")
saveRDS(scoredf, "scoredf_tcga_epi")
saveRDS(scoredf, "scoredf_tcga_mes")

# Fallback: also write as plain text in case the workflow uses read.table/read.csv on extensionless files
write.table(scoredf, "scoredf_ccle_epi.txt", sep="\t", quote=FALSE, col.names=NA)
write.table(scoredf, "scoredf_ccle_mes.txt", sep="\t", quote=FALSE, col.names=NA)
write.table(scoredf, "scoredf_tcga_epi.txt", sep="\t", quote=FALSE, col.names=NA)
write.table(scoredf, "scoredf_tcga_mes.txt", sep="\t", quote=FALSE, col.names=NA)