# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("karyoploteR", "regioneR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(karyoploteR)
library(regioneR)

set.seed(123)

# Reproducing the vignette's exact data generation code
rand.data <- createRandomRegions(
    genome="hg19", 
    nregions=1000, 
    length.mean=1, 
    length.sd=0, 
    mask=NA, 
    non.overlapping=TRUE
)
rand.data <- toDataframe(sort(rand.data))
rand.data <- cbind(rand.data, y=runif(n=1000, min=-1, max=1))

# Select some data points as "special ones"
sel.data <- rand.data[c(7, 30, 38, 52),]

# Serialize the objects to the declared input files
saveRDS(rand.data, "rand.data")
saveRDS(sel.data, "sel.data")