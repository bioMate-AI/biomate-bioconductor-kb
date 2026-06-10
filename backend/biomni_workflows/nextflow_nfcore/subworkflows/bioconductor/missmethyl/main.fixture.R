# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("missMethyl", "minfi", "minfiData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(missMethyl)
library(minfi)
library(minfiData)

# 1. Get the base directory for minfiData's example data
minfiData_baseDir <- system.file("extdata", package = "minfiData")

# 2. Read the original targets sheet from minfiData
targets_orig <- read.metharray.sheet(minfiData_baseDir)

# 3. Prepare the new targets data frame for the current directory
# This data frame will be saved as SampleSheet.csv
targets <- targets_orig

# Modify the Basename column to be relative to the current working directory.
# The original Basename looks like: /path/to/minfiData/extdata/SLIDE_ID/BASENAME
# We want it to be: SLIDE_ID/BASENAME
targets$Basename <- sub(paste0(minfiData_baseDir, "/"), "", targets_orig$Basename)

# 4. Create necessary directories and copy IDAT files to the current working directory
unique_basenames_orig <- unique(targets_orig$Basename)
unique_basenames_relative <- unique(targets$Basename)

for (i in seq_along(unique_basenames_orig)) {
  src_basename <- unique_basenames_orig[i]
  dest_basename <- unique_basenames_relative[i]

  # Source IDAT file paths from the minfiData package
  src_grn_idat <- paste0(src_basename, "_Grn.idat")
  src_red_idat <- paste0(src_basename, "_Red.idat")

  # Determine the destination directory (e.g., "5723646052")
  dest_dir <- dirname(dest_basename)
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Destination IDAT file paths in the current working directory
  dest_grn_idat <- paste0(dest_basename, "_Grn.idat")
  dest_red_idat <- paste0(dest_basename, "_Red.idat")

  # Copy the IDAT files