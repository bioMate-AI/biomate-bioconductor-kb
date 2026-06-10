library(scCB2)
library(SummarizedExperiment)
library(DropletUtils)

# Load the example dataset from the scCB2 package
data(mbrainSub, package = "scCB2")

# 1. Create the raw_data_directory (10x Cell Ranger output directory format)
if (dir.exists("raw_data_directory")) {
    unlink("raw_data_directory", recursive = TRUE)
}
DropletUtils::write10xCounts("raw_data_directory", mbrainSub, version = "3")

# 2. Create the raw_data_HDF5 (10x raw data in HDF5 format)
if (file.exists("raw_data_HDF5")) {
    unlink("raw_data_HDF5")
}
DropletUtils::write10xCounts("raw_data_HDF5", mbrainSub, type = "HDF5")