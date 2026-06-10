# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MSnID")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MSnID)

# Locate the 'human_brain.txt' file from the MSnID package's extdata directory
human_brain_src <- system.file("extdata", "human_brain.txt", package="MSnID")
# Copy the file to the current working directory with the specified name
file.copy(human_brain_src, "human_brain.txt", overwrite = TRUE)

# Locate the 'c_elegans.mzid.gz' file from the MSnID package's extdata directory
c_elegans_src <- system.file("extdata", "c_elegans.mzid.gz", package="MSnID")
# Copy the file to the current working directory with the specified name
file.copy(c_elegans_src, "c_elegans.mzid.gz", overwrite = TRUE)