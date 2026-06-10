library(scCB2)
library(SummarizedExperiment)
library(DropletUtils)

# Load the example dataset from the scCB2 package
data(mbrainSub, package = "scCB2")

# The workflow expects a directory named "raw_data_directory"
data.dir <- "raw_data_directory"

# Clean up if it already exists to avoid write10xCounts errors
if (dir.exists(data.dir)) {
    unlink(data.dir, recursive = TRUE)
}

# Write the 10x counts to the directory in Cell Ranger version 3 format
# This generates barcodes.tsv.gz, features.tsv.gz, and matrix.mtx.gz
DropletUtils::write10xCounts(data.dir, mbrainSub, version = "3")