# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scds", "scater", "rsvd", "Rtsne")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scds)
library(scater)
library(rsvd)
library(Rtsne)
set.seed(30519)
data("sce_chcl")
sce = sce_chcl
logcounts(sce) = log1p(counts(sce))
vrs = apply(logcounts(sce),1,var)
pc = rpca(t(logcounts(sce)[order(vrs,decreasing=TRUE)[1:100],]))
ts = Rtsne(pc$x[,1:10],verb=FALSE)
reducedDim(sce,"tsne") = ts$Y; rm(ts,vrs,pc)
saveRDS(sce, file = "sce.rds")