# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Mfuzz")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Mfuzz)

data(yeast) 
yeast.r <- filter.NA(yeast, thres=0.25)
yeast.f <- fill.NA(yeast.r, mode="mean")
yeast.s <- standardise(yeast.f)

cl <- mfuzz(yeast.s, c=16, m=1.25)

saveRDS(yeast.s, "yeast.s")
saveRDS(cl, "cl")