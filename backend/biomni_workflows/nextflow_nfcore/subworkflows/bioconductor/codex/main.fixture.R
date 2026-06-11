# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CODEX", "WES.1KG.WUGSC")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CODEX)
library(WES.1KG.WUGSC)

# Get the path to the extdata directory of the WES.1KG.WUGSC package
dirPath <- system.file("extdata", package = "WES.1KG.WUGSC")

# Identify the specific input files used in the vignette
bamFiles_in_package <- list.files(dirPath, pattern = '*.bam$', full.names = TRUE)
bedFile_in_package <- file.path(dirPath, "chr22_400_to_500.bed")
sampnameFile_in_package <- file.path(dirPath, "sampname")

# Copy the identified files to the current working directory
# The workflow expects these files to be in the working directory.
file.copy(from = bamFiles_in_package, to = basename(bamFiles_in_package), overwrite = TRUE)
file.copy(from = bedFile_in_package, to = basename(bedFile_in_package), overwrite = TRUE)
file.copy(from = sampnameFile_in_package, to = basename(sampnameFile_in_package), overwrite = TRUE)