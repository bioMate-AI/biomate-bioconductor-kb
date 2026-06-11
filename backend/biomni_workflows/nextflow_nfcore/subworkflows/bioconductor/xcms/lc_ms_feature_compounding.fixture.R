library(MSnbase)
library(xcms)
library(faahKO)

# The vignette uses MsDataHub which fetches data from Zenodo (requires internet).
# To ensure strict offline execution, we use the faahKO package (present in the 
# vignette's sessionInfo) which ships with raw CDF files.
mzML_files <- list.files(system.file("cdf", package = "faahKO"), 
                         recursive = TRUE, full.names = TRUE)[1:2]

# Create a data.frame assigning samples to sample groups
grp <- c("KO", "KO")
pd <- data.frame(filename = basename(mzML_files), sample_group = grp)
rownames(pd) <- pd$filename

# Load the data
ham_raw <- readMSData(files = mzML_files, pdata = AnnotatedDataFrame(pd), mode = "onDisk")

# Define the parameters for the peak detection
# Using CentWaveParam as faahKO is LC-MS data (unlike the direct injection in the vignette)
cwp <- CentWaveParam(snthresh = 10, noise = 1000)
xmse <- findChromPeaks(ham_raw, param = cwp)

# Save the preprocessed XCMSnExp object to the expected input file
saveRDS(xmse, "xmse")