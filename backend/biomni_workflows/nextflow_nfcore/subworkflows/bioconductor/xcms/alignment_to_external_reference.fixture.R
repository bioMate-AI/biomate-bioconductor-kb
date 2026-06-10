library(MSnbase)
library(xcms)
library(faahKO)

register(SerialParam())

# Use faahKO data as a reliable offline alternative to the downloaded MsDataHub data
mzML_files <- list.files(system.file("cdf", package = "faahKO"), full.names = TRUE, recursive = TRUE)[1:4]

# Create a data.frame assigning samples to sample groups
grp <- c("ham4", "ham4", "ham5", "ham5")
pd <- data.frame(filename = basename(mzML_files), sample_group = grp)

# Load the data
ham_raw <- readMSData(files = mzML_files, pdata = AnnotatedDataFrame(pd), mode = "onDisk")

# Define the parameters for the peak detection
# Using CentWaveParam instead of MSWParam since faahKO is LC-MS data
cwp <- CentWaveParam(snthresh = 10, noise = 1000, peakwidth = c(20, 50))
ham_prep <- findChromPeaks(ham_raw, param = cwp)

# Correspondence
# Using PeakDensityParam instead of MzClustParam for LC-MS data
pdp <- PeakDensityParam(sampleGroups = ham_prep$sample_group)
ham_prep <- groupChromPeaks(ham_prep, param = pdp)

# Save the resulting object to the required input files
saveRDS(ham_prep, "ref.rds")
saveRDS(ham_prep, "tst.rds")