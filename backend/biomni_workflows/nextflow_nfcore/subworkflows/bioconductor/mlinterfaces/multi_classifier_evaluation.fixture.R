# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MASS", "MLInterfaces")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MASS)
library(MLInterfaces)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette uses the 'crabs' dataset from the 'MASS' package.
# Section 2.1: "Attaching and checking the data"
data("crabs")

# Section 2.4: "First let us use MLearn from the MLInterfaces package to fit a single logistic model."
# The vignette then creates 'fcrabs' and 'sfcrabs' objects which are used with MLearn.
# "fcrabs = crabs[crabs$sex == "F", ]"
fcrabs = crabs[crabs$sex == "F", ]

# Section 2.4: "First, we scramble the order of records in the ExpressionSet so that sequentially formed groups are approximately random samples."
# "set.seed(123)"
# "sfcrabs = fcrabs[ sample(nrow(fcrabs)), ]"
set.seed(123)
sfcrabs = fcrabs[ sample(nrow(fcrabs)), ]

# The object 'sfcrabs' is the final prepared dataset used in the MLInterfaces examples
# for cross-validation in the vignette.

# 2. Serialize that object to EACH declared input file (crES)
# The workflow reads "crES.rds" or "crES" using readRDS.
# We will save the 'sfcrabs' object to "crES.rds" to match the workflow's read format.
saveRDS(sfcrabs, "crES.rds")