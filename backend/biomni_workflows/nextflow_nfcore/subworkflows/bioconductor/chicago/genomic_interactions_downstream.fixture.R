# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Chicago", "PCHiCdata")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Chicago)
library(PCHiCdata)

# Reproduce the vignette's data preparation for the 'cd' object
dataPath <- system.file("extdata", package="PCHiCdata")
testDesignDir <- file.path(dataPath, "hg19TestDesign")
testDataPath <- file.path(dataPath, "GMchinputFiles")

files <- c(
  file.path(testDataPath, "GM_rep1.chinput"),
  file.path(testDataPath, "GM_rep2.chinput"),
  file.path(testDataPath, "GM_rep3.chinput")
)

settingsFile <- file.path(system.file("extdata", package="PCHiCdata"), "sGM12878Settings", "sGM12878.settingsFile")

cd <- setExperiment(designDir = testDesignDir, settingsFile = settingsFile)
cd <- readAndMerge(files=files, cd=cd)

# Serialize the 'cd' object to a file named 'cd'
# The 'cd' object is an S4 object, so saveRDS is the appropriate serialization method.
saveRDS(cd, "cd.rds")

# The vignette does not provide data preparation code for 'enhancerTrack'.
# It is mentioned as an input for a downstream analysis function (peakEnrichment4Features)
# with the note "You will need additional files to perform".
# As per instructions, we cannot invent data or guess formats not explicitly shown in the vignette.
# Therefore, 'enhancerTrack' cannot be generated based on the provided vignette code.