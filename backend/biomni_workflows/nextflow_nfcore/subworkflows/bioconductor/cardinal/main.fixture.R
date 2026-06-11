library(Cardinal)
library(CardinalIO)

# Get paths to the example files provided by CardinalIO
path_continuous <- CardinalIO::exampleImzMLFile("continuous")
path_processed <- CardinalIO::exampleImzMLFile("processed")

# Copy the continuous imzML and its corresponding ibd file to the working directory
file.copy(path_continuous, "continuous.imzML", overwrite = TRUE)
ibd_continuous <- sub("\\.imzML$", ".ibd", path_continuous, ignore.case = TRUE)
if (file.exists(ibd_continuous)) {
    file.copy(ibd_continuous, "continuous.ibd", overwrite = TRUE)
}

# Copy the processed imzML and its corresponding ibd file to the working directory
file.copy(path_processed, "processed.imzML", overwrite = TRUE)
ibd_processed <- sub("\\.imzML$", ".ibd", path_processed, ignore.case = TRUE)
if (file.exists(ibd_processed)) {
    file.copy(ibd_processed, "processed.ibd", overwrite = TRUE)
}