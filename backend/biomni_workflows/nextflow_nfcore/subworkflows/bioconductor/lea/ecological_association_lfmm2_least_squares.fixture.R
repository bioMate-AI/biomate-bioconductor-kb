# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("LEA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(LEA)

# Reproduce the vignette's data-preparation code for Y and X
data("offset_example")
Y <- offset_example$geno
X <- offset_example$env

# Serialize Y to the input file "Y.rds"
# The workflow's read_input function prioritizes .rds files.
saveRDS(Y, "Y.rds")

# Serialize X to the input file "X.rds"
# The workflow's read_input function prioritizes .rds files.
saveRDS(X, "X.rds")