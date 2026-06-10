# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CFAssay")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CFAssay)

# Reproduce the vignette's data-preparation code to materialize the example object.
# This uses the first dataset presented in the vignette, 'expl1_cellsurvcurves.txt',
# which is used for the linear-quadratic model analysis.
datatab <- read.table(system.file("doc", "expl1_cellsurvcurves.txt",
                                  package="CFAssay"), header=TRUE, sep="\t")

# Serialize the 'datatab' object to the declared input file 'cellsurv_data.txt'.
# The format matches the workflow's read.table call: tab-separated, with header, no row names.
write.table(datatab, "cellsurv_data.txt", row.names=FALSE, col.names=TRUE, sep="\t", quote=FALSE)