# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("blacksheepr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(blacksheepr)

# Reproduce the vignette's data-preparation code
data("sample_annotationdata")
comptable <- sample_annotationdata

data("sample_phosphodata")
phosphotable <- sample_phosphodata

# Serialize the objects to the declared input files in the exact format the workflow reads
write.csv(comptable, "comptable.csv", row.names = TRUE, quote = FALSE)
write.csv(phosphotable, "phosphotable.csv", row.names = TRUE, quote = FALSE)