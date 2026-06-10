# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("macrophage", "tximeta", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(macrophage))
suppressPackageStartupMessages(library(tximeta))
suppressPackageStartupMessages(library(SummarizedExperiment))

# Define the path to the macrophage package's extdata directory
macrophage_extdata_dir <- system.file("extdata", package="macrophage")

# Read the original coldata.csv from the macrophage package
coldata_orig <- read.csv(file.path(macrophage_extdata_dir, "coldata.csv"))

# Perform vignette's coldata transformations
# Subset to certain columns of interest, and re-name them
coldata_orig <- coldata_orig[, c(1, 2, 3, 5)]
names(coldata_orig) <- c("names", "id", "line", "condition")

# Subset to "naive" and "IFNg" groups and set factor levels
coldata_orig <- coldata_orig[coldata_orig$condition %in% c("naive", "IFNg"),]
coldata_orig$condition <- factor(coldata_orig$condition, levels=c("naive", "IFNg"))

# Create the coldata data frame for the output, with paths relative to the working directory
coldata_output <- coldata_orig
coldata_output$files <- file.path("quants", coldata_output$names, "quant.sf.gz")

# Write coldata_output to coldata.csv in the current working directory
write.csv(coldata_output, "coldata.csv", row.names=FALSE)

# Identify the unique sample names from coldata_output
sample_names <- unique(coldata_output$names)

# For each sample, copy its Salmon quantification directory to the working directory
for (sample_name in sample_names) {
  src_dir <- file.path(macrophage_extdata_dir, "quants", sample_name)
  dest_dir <- file.path("quants", sample_name)

  # Create the destination directory if it doesn't exist
  dir.create(dest_dir, recursive=TRUE, showWarnings=FALSE)

  # Get all items (files and subdirectories) within src_dir
  items_to_copy <- list.files(src_dir, full.names = TRUE)

  # Copy them to dest_dir
  file.copy(from = items_to_copy,
            to = dest_dir,
            recursive = TRUE,
            copy.mode = TRUE)
}