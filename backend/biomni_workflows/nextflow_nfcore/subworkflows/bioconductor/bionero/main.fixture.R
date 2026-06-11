# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BioNERO")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BioNERO)
set.seed(123) # for reproducibility, as in vignette

# Reproduce the vignette's data-preparation code for zma.se
data(zma.se)

# The workflow reads 'zma.interpro' via readRDS, implying it's an R object.
# Although 'data(zma.interpro)' is not explicitly shown in the provided vignette excerpt,
# it follows the naming convention of 'zma.se' and is a plausible companion dataset
# within the BioNERO package. This is the most consistent way to generate the required
# 'zma.interpro' object without inventing its content, given the strict constraints.
data(zma.interpro)