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
library(fishpond)

# Define the path to the extdata directory of the macrophage package
macrophage_extdata_dir <- system.file("extdata", package="macrophage")

# Read the initial coldata.csv from the macrophage package
coldata <- read.csv(file.path(macrophage_extdata_dir, "coldata.csv"))

# Subset and rename columns as per the vignette
coldata <- coldata[, c(1, 2, 3, 5)]
names(coldata) <- c("names", "id", "line", "condition")

# Filter coldata for "naive" and "IFNg" conditions and set factor levels
coldata <- coldata[coldata$condition %in% c("naive", "IFNg"),]
coldata$condition <- factor(coldata$condition, levels=c("naive", "IFNg"))

# Define the output directory for quantification files in the current working directory
output_quants_base_dir <- "quants"
if (!dir.exists(output_quants_base_dir)) {
  dir.create(output_quants_base_dir)
}

# Prepare a vector to store the new relative file paths for coldata
new_files_paths <- character(nrow(coldata))

# Loop through each sample in the filtered coldata to copy quantification files
for (i in seq_len(nrow(coldata))) {
  sample_name <- coldata$names[i]
  
  # Construct the source path for the quant.sf.gz file within the macrophage package
  source_quant_file <- file.path(macrophage_extdata_dir, "quants", sample_name, "quant.sf.gz")
  
  # Construct the destination directory path for the sample within the output_quants_base_dir
  dest_sample_dir <- file.path(output_quants_base_dir, sample_name)
  
  # Create the destination directory if it doesn't exist
  if (!dir.exists(dest_sample_dir)) {
    dir.create(dest_sample_dir)
  }
  
  # Construct the full destination file path
  dest_quant_file <- file.path(dest_sample_dir, "quant.sf.gz")
  
  # Copy the quant.sf.gz file from the package's extdata to the working directory
  file.copy(from = source_quant_file, to = dest_quant_file, overwrite = TRUE)
  
  # Store the relative path to the copied file for the coldata$files column
  new_files_paths[i] <- file.path(output_quants_base_dir, sample_name, "quant.sf.gz")
}

# Add the 'files' column with the relative paths to the coldata data frame
coldata$files <- new_files_paths

# Write the final coldata data frame to coldata.csv in the working directory
write.csv(coldata, "coldata.csv", row.names = FALSE)