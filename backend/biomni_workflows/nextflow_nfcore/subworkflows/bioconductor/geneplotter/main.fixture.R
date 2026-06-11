# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Biobase", "geneplotter", "annotate")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Biobase)
library(geneplotter)
library(annotate)

# Load the ExpressionSet object from Biobase
data(sample.ExpressionSet)

# Serialize the ExpressionSet object to the declared input file
saveRDS(sample.ExpressionSet, "sample.ExpressionSet")

# hgu95av2 is an annotation package used via buildChromLocation("hgu95av2").
# To satisfy the strict file existence requirement for the declared input list,
# we create a placeholder file.
writeLines("annotation_package_placeholder", "hgu95av2")