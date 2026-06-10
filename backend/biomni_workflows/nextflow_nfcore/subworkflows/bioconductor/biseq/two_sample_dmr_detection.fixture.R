# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BiSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BiSeq)

data(rrbs)
rrbs.small <- rrbs[1:1000,]
rrbs.clust.unlim <- clusterSites(object = rrbs.small,
                                 groups = colData(rrbs)$group,
                                 perc.samples = 4/5,
                                 min.sites = 20,
                                 max.dist = 100)

ind.cov <- totalReads(rrbs.clust.unlim) > 0
quant <- quantile(totalReads(rrbs.clust.unlim)[ind.cov], 0.9)
rrbs.clust.lim <- limitCov(rrbs.clust.unlim, maxCov = quant)

predictedMeth <- predictMeth(object = rrbs.clust.lim)

saveRDS(predictedMeth, "predictedMeth")