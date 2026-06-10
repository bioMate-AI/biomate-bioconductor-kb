library(xcms)
library(faahKO)

# The vignette uses MsDataHub which fetches from Zenodo (violating the OFFLINE rule).
# We instead use the faahKO package (present in the vignette's sessionInfo) 
# which ships with offline CDF files for LC-MS data.
cdf_paths <- list.files(system.file("cdf", package = "faahKO"), 
                        pattern = "\\.CDF$", 
                        recursive = TRUE, 
                        full.names = TRUE)

# Copy the CDF files to the working directory to serve as the 'cdfs' input
for (f in head(cdf_paths, 4)) {
    file.copy(from = f, to = basename(f), overwrite = TRUE)
}