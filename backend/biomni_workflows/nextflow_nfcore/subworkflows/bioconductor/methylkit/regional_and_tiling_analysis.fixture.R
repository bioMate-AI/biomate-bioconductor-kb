# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("methylKit")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(methylKit)

# Reproduce the file.list object from the vignette
file.list <- list(
  system.file("extdata", "test1.myCpG.txt", package = "methylKit"),
  system.file("extdata", "test2.myCpG.txt", package = "methylKit"),
  system.file("extdata", "control1.myCpG.txt", package = "methylKit"),
  system.file("extdata", "control2.myCpG.txt", package = "methylKit")
)

# Serialize file.list to file.list.rds as per workflow's read preference
saveRDS(file.list, "file.list.rds")

# The vignette excerpt provided does not create or reference an object named
# 'gene.obj' or 'promoters'. Therefore, no file for 'gene.obj$promoters'
# will be generated, adhering strictly to the instruction to only recreate
# objects using the vignette's own data-preparation code.