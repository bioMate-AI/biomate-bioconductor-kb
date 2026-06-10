# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("dagLogo")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(dagLogo)

# Reproduce the vignette's own data-preparation code to materialize the example object.
# The vignette itself loads 'peptides4dagLogo.csv' from its 'extdata' directory.
# We will load it from there and then write it to the working directory.
dat_path <- system.file("extdata", "peptides4dagLogo.csv", package = "dagLogo")
dat <- read.csv(dat_path)

# Serialize the 'dat' object to 'peptides4dagLogo.csv' in the working directory
# in the exact format the workflow reads (CSV, without row names).
write.csv(dat, "peptides4dagLogo.csv", row.names = FALSE)