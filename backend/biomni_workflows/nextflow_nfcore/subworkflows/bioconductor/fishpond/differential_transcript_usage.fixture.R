# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("macrophage", "tximeta", "SummarizedExperiment", "fishpond")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(macrophage)
library(tximeta)
library(SummarizedExperiment)
library(fishpond) # Included as per prompt, though not directly used for file generation

# Get the path to the extdata directory of the macrophage package
macrophage_extdata_dir <- system.file("extdata", package = "macrophage")

# Read the original coldata.csv from the macrophage package
original_coldata <- read.csv(file.path(macrophage_extdata_dir, "coldata.csv"))

# Subset and rename columns as per vignette
coldata_modified <- original_coldata[, c(1, 2, 3, 5)]
names(coldata_modified) <- c("names", "id", "line", "condition")

# Subset to "naive" and "IFNg" conditions and set factor levels
coldata_final <- coldata_modified[coldata_modified$condition %in% c("naive", "IFNg"), ]
coldata_final$condition <- factor(coldata_final$condition, levels = c("naive", "IFNg"))

# Create the base directory for Salmon quantification files in the current working directory
dir.create("quants", showWarnings = FALSE)

# Iterate through the samples in coldata_final to copy their Salmon quantification files
for (i in seq_len(nrow(coldata_final))) {
  sample_name <- coldata_final$names[i]

  # Source path in the macrophage package
  src_quant_dir <- file.path(macrophage_extdata_dir, "quants", sample_name)
  src_quant_file <- file.path(src_quant_dir, "quant.sf.gz")

  # Destination path in the current working directory
  dest_quant_dir <- file.path("quants", sample_name)
  dest_quant_file <- file.path(dest_quant_dir, "quant.sf.gz")

  # Create the destination directory for the sample
  dir.create(dest_quant_dir, recursive = TRUE, showWarnings = FALSE)

  # Copy the quant.sf.gz file
  if (file.exists(src_quant_file)) {
    file.copy(src_quant_file, dest_quant_file, overwrite = TRUE)
  } else {
    stop(paste("Source quantification file not found:", src_quant_file))
  }
}

# Update the 'files' column in coldata_final to point to the newly created local paths
coldata_final$files <- file.path("quants", coldata_final$names, "quant.sf.gz")

# Write the final coldata object to coldata.csv
write.csv(coldata_final, "coldata.csv", row.names = FALSE)