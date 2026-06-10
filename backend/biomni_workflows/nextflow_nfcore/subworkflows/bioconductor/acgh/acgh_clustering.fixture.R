# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("aCGH")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(aCGH)

# Load the colorectal dataset as described in vignette chunk 4
data(colorectal)

# Replicate the data preparation steps for 'colorectal.na' from vignette chunk 17
# This creates the 'colorectal.na' object by subsetting the 'colorectal' object
# based on sex information and chromosome number.
sex <- phenotype(colorectal)$sex
sex.na <- !is.na(sex)
index.clones.use <- which(clones.info(colorectal)$Chrom < 23)
colorectal.na <- colorectal[ index.clones.use,sex.na , keep=TRUE]

# Serialize the 'colorectal.na' object to an RDS file,
# matching the workflow's input file name and format.
saveRDS(colorectal.na, file = "colorectal.na")