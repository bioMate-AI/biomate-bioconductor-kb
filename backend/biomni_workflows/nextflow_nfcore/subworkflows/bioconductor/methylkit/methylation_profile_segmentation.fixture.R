# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("methylKit")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(methylKit)

# Reproduce the vignette's data-preparation code
file.list=list(
  system.file("extdata", "test1.myCpG.txt", package = "methylKit"),
  system.file("extdata", "test2.myCpG.txt", package = "methylKit"),
  system.file("extdata", "control1.myCpG.txt", package = "methylKit"),
  system.file("extdata", "control2.myCpG.txt", package = "methylKit")
)

# read the files to a methylRawList object: myobj
myobj=methRead(file.list, sample.id=list("test1","test2","ctrl1","ctrl2"), assembly="hg18", treatment=c(1,1,0,0), context="CpG", mincov = 10 )

# Create the methylBase object 'meth' which is the main object for comparative analysis
meth=unite(myobj, destrand=FALSE)

# Serialize the 'meth' object to 'mbw.rds' as the workflow expects 'mbw' via readRDS
saveRDS(meth, file = "mbw.rds")