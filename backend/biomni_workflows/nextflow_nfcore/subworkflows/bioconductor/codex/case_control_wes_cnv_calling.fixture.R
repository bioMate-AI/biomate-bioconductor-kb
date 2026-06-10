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

# Determine the path to the example data within the WES.1KG.WUGSC package
dirPath <- system.file("extdata", package = "WES.1KG.WUGSC")

# Identify the specific input files used by the vignette
# These are the files the workflow expects to read from the working directory.

# 1. BAM files
# Get full paths to BAM files in the package's extdata
bamFiles_in_package <- list.files(dirPath, pattern = '*.bam$', full.names = TRUE)
# Get just the filenames for copying to the current directory
bamNames_short <- list.files(dirPath, pattern = '*.bam$', full.names = FALSE)

# 2. BED file
bedFile_in_package <- file.path(dirPath, "chr22_400_to_500.bed")
bedName_short <- "chr22_400_to_500.bed"

# 3. sampname file
sampnameFile_in_package <- file.path(dirPath, "sampname")
sampnameName_short <- "sampname"

# Copy these identified files from the package's extdata to the current working directory.
# This action "serializes" the vignette's example data into the required input files
# in the exact format the workflow reads.

# Copy BAM files
for (i in seq_along(bamFiles_in_package)) {
  file.copy(from = bamFiles_in_package[i], to = bamNames_short[i], overwrite = TRUE)
}

# Copy BED file
file.copy(from = bedFile_in_package, to = bedName_short, overwrite = TRUE)

# Copy sampname file
file.copy(from = sampnameFile_in_package, to = sampnameName_short, overwrite = TRUE)