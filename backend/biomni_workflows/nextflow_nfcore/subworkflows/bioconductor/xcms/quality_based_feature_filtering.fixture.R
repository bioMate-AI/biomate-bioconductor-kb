library(xcms)
library(faahKO)

# Locate the CDF files shipped with the faahKO package
cdfpath <- system.file("cdf", package = "faahKO")
cdffiles <- list.files(cdfpath, recursive = TRUE, full.names = TRUE)

# Use a subset of files to ensure the script runs quickly
cdffiles <- cdffiles[1:2]

# Create a data.frame describing the experimental setup
pd <- data.frame(
    filename = basename(cdffiles),
    sample_group = c("KO", "KO"),
    stringsAsFactors = FALSE
)

# Load the raw MS data
raw_data <- readMSData(
    files = cdffiles, 
    pdata = new("NAnnotatedDataFrame", pd), 
    mode = "onDisk"
)

# Define parameters for peak detection (CentWave is standard for LC-MS faahKO data)
cwp <- CentWaveParam(snthresh = 10, noise = 1000, peakwidth = c(20, 50))

# Perform chromatographic peak detection
xdata <- findChromPeaks(raw_data, param = cwp)

# Save the preprocessed XcmsExperiment / XCMSnExp object to the expected input file
saveRDS(xdata, "faahko.rds")