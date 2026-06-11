# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CellNOptR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CellNOptR)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
#    The vignette's "Quick Start" section provides the exact code to load
#    the example data objects.
data("ToyModel", package="CellNOptR")
data("CNOlistToy", package="CellNOptR")

# Assign ToyModel to pknmodel as done in the vignette
pknmodel <- ToyModel

# Convert CNOlistToy to a CNOlist object as done in the vignette
cnolist <- CNOlist(CNOlistToy)

# 2. Serialize objects to the declared input files
#    The workflow reads ToyPKNMMB.sif using readSIF, so we use writeSIF.
writeSIF(pknmodel, "ToyPKNMMB.sif")

#    The workflow reads ToyDataMMB.csv using readMIDAS, so we use writeMIDAS.
writeMIDAS(cnolist, "ToyDataMMB.csv")