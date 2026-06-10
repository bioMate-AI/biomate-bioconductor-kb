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

# Locate the CDF files shipped with the faahKO package (offline data)
cdfpath <- system.file("cdf", package = "faahKO")
cdffiles <- list.files(cdfpath, recursive = TRUE, full.names = TRUE)[1:2]

# Create a data.frame describing the experimental setup
pd <- data.frame(
    filename = basename(cdffiles),
    sample_group = c("KO", "KO"),
    stringsAsFactors = FALSE
)

# Read the data into an MsExperiment object
raw_data <- readMsExperiment(spectraFiles = cdffiles, sampleData = pd)

# Define parameters for peak detection
# Using CentWaveParam as it is appropriate for the LC-MS data in faahKO
cwp <- CentWaveParam(peakwidth = c(20, 50), noise = 1000)

# Perform peak detection to generate the preprocessed XcmsExperiment object
xmse <- findChromPeaks(raw_data, param = cwp)

# Save the preprocessed XcmsExperiment object to the required input file
saveRDS(xmse, "xmse.rds")