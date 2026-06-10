# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("karyoploteR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(karyoploteR)

gains <- toGRanges(data.frame(
    chr=c("chr1", "chr5", "chr17", "chr22"), 
    start=c(1, 1000000, 4000000, 1), 
    end=c(5000000, 3200000, 80000000, 1200000)
))

losses <- toGRanges(data.frame(
    chr=c("chr3", "chr9", "chr17"), 
    start=c(80000000, 20000000, 1), 
    end=c(170000000, 30000000, 25000000)
))

saveRDS(gains, "gains")
saveRDS(losses, "losses")