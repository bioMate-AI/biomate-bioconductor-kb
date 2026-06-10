library(MSnbase)
library(xcms)
library(faahKO)
library(Biobase)

# The vignette uses MsDataHub which downloads from Zenodo.
# To ensure the script runs fully offline, we use the faahKO package 
# (present in the vignette's sessionInfo) which ships with local CDF files.
mzML_files <- list.files(system.file("cdf", "KO", package = "faahKO"), 
                         full.names = TRUE)[1:2]

# Create a data.frame assigning samples to sample groups
grp <- c("KO", "KO")
pd <- data.frame(filename = basename(mzML_files), sample_group = grp)

# Load the data
ham_raw <- readMSData(files = mzML_files, 
                      pdata = AnnotatedDataFrame(pd), 
                      mode = "onDisk")

# Since faahKO is LC-MS data (unlike the direct injection data in the vignette),
# we use CentWaveParam instead of MSWParam for peak detection.
cwp <- CentWaveParam(snthresh = 10, noise = 1000, ppm = 25, peakwidth = c(20, 50))
ham_prep <- findChromPeaks(ham_raw, param = cwp)

# Correspondence (grouping) using PeakDensityParam for LC-MS
pdp <- PeakDensityParam(sampleGroups = ham_prep$sample_group)
ham_prep <- groupChromPeaks(ham_prep, param = pdp)

# Save the preprocessed XCMSnExp object to the expected input file
saveRDS(ham_prep, "xmse.rds")