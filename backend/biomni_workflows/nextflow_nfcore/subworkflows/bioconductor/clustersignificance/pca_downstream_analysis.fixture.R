# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ClusterSignificance")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ClusterSignificance)

# Reproduce the vignette's data-preparation code
data(pcpMatrix)

# Materialize the expression matrix
expression_matrix <- pcpMatrix

# Materialize the classes vector
classes_vector <- rownames(pcpMatrix)

# Serialize the expression matrix to the 'expression' file using saveRDS
saveRDS(expression_matrix, "expression")

# Serialize the classes vector to the 'classes' file using saveRDS
saveRDS(classes_vector, "classes")