# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AgiMicroRna")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("AgiMicroRna")

# 1. Reproduce the vignette's data-preparation code
# Load targets.micro and dd.micro objects from the package's example data
data(targets.micro)
data(dd.micro)

# 2. Serialize targets.micro to "targets.txt"
# The vignette describes targets.txt as a tab-delimited file.
# Table 1 in the vignette shows the structure.
write.table(targets.micro, file = "targets.txt", sep = "\t", quote = FALSE, row.names = FALSE)

# 3. Serialize the data contained within dd.micro to individual "Scanned Agilent image data files"
# The dd.micro object is a Micro