# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("viper", "bcellViper")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(viper)
library(bcellViper)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code to materialize the example object.
# The 'dset' object is loaded from the bcellViper package.
data(bcellViper, package="bcellViper")

# The 'bcellaracne.adj' file is located within the bcellViper package.
adjfile_source <- system.file("aracne", "bcellaracne.adj", package = "bcellViper")

# 2. Serialize that object to EACH declared input file in the EXACT format the workflow reads.

# For 'dset': The workflow reads it using readRDS("dset").
saveRDS(dset, "dset.rds")

# For 'bcellaracne.adj': The workflow expects this file to be in the working directory.
# We copy it from its installed location in the bcellViper package.
file.copy(adjfile_source, "bcellaracne.adj", overwrite = TRUE)