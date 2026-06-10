# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("xcms", "MsExperiment", "faahKO")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(xcms)
library(MsExperiment)
library(faahKO)

# The vignette uses MsDataHub which downloads data from Zenodo.
# To strictly comply with the OFFLINE requirement, we use the faahKO package 
# (present in the vignette's sessionInfo) which ships local mzCDF files.

# Locate mzCDF files shipped with faahKO
cdf_files <- list.files(system.file("cdf", package = "faahKO"), 
                        recursive = TRUE, full.names = TRUE)[1:2]

# Read data into an MsExperiment
mse <- readMsExperiment(spectraFiles = cdf_files)

# Add sample information
mse$sample_group <- c("KO", "KO")

# Perform peak detection to create an XcmsExperiment object
# Using MatchedFilterParam which is suitable for the faahKO LC-MS dataset
prm <- MatchedFilterParam(snthresh = 10, fwhm = 30)
xmse <- findChromPeaks(mse, param = prm)

# Save the XcmsExperiment objects to the required files
saveRDS(xmse, "ref.rds")
saveRDS(xmse, "tst.rds")