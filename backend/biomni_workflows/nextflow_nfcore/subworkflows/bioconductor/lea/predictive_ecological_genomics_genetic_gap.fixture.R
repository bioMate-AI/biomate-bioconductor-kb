# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("LEA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(LEA)

# Reproduce the vignette's data-preparation code
data("offset_example")

# Serialize the objects to the declared input files in the exact format the workflow reads
# Y corresponds to offset_example$geno, written as Y.lfmm
LEA::write.lfmm(offset_example$geno, "Y.lfmm")

# X corresponds to offset_example$env, written as X.env
LEA::write.env(offset_example$env, "X.env")

# X.pred corresponds to offset_example$env.pred, written as X.pred.env
LEA::write.env(offset_example$env.pred, "X.pred.env")