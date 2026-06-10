# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("LEA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(LEA)

# The vignette creates a directory and changes into it.
# For a self-contained test fixture, we will write directly to the current working directory.
# dir.create("LEA_analyses")
# setwd("LEA_analyses")

# Load the tutorial dataset as shown in the vignette
data("tutorial")

# Write genotypes in the lfmm format
write.lfmm(tutorial.R, "genotypes.lfmm")

# Write genotypes in the geno format
write.geno(tutorial.R, "genotypes.geno")