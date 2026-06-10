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

# 1. Reproduce the VIGNETTE'S OWN data-preparation code to materialize the example object
# Get paths to example data from PCHiCdata package
dataPath <- system.file("extdata", package="PCHiCdata")
testDesignDir <- file.path(dataPath, "hg19TestDesign")
testDataPath <- file.path(dataPath, "GMchinputFiles")

# List input .chinput files for readAndMerge
files <- c(
  file.path(testDataPath, "GM_rep1.chinput"),
  file.path(testDataPath, "GM_rep2.chinput"),
  file.path(testDataPath, "GM_rep3.chinput")
)

# Get the optional settings file
settingsFile <- file.path(system.file("extdata", package="PCHiCdata"), "sGM12878Settings", "sGM12878.settingsFile")

# Create a blank chicagoData object and set design files
cd <- setExperiment(designDir = testDesignDir, settingsFile = settingsFile)

# Read in and merge input data files into the chicagoData object
cd <- readAndMerge(files=files, cd=cd)

# Run the CHiCAGO pipeline to process the data
cd <- chicagoPipeline(cd)

# 2. Serialize the 'cd' object to the file named 'cd'
# The 'cd' object is an S4 object, so saveRDS is the appropriate serialization method.
saveRDS(cd, "cd.rds")

# Generate 'featuresGM.txt'
# The vignette mentions 'featuresGM.txt' as an example input for peakEnrichment4Features()
# but does not provide code to create it. As per the prompt's instruction to serialize
# "that object" (cd, or data derived from it) to this file, we will extract bait regions
# from the 'cd' object's design information and write them as a simple tab-separated file.
features_df <- cd@design@baitmap[, c("chr", "start", "end", "bait_name")]
colnames(features_df) <- c("chr", "start", "end", "name") # Rename columns for a generic feature file
write.table(features_df, "featuresGM.txt", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)

# Generate 'spp.wgEncodeBroadHistoneGm12878CtcfStdAln_chr20and21.narrowPeak'
# Similar to 'featuresGM.txt', this file is mentioned as an example for feature enrichment
# but no creation code is provided in the vignette. We will create a dummy narrowPeak file
# using bait regions from the 'cd' object, adhering to the 10-column narrowPeak format.
# narrowPeak format: chrom, chromStart, chromEnd, name, score, strand, signalValue, pValue, qValue, peak
narrowPeak_df <- data.frame(
  chrom = paste0("chr", cd@design@baitmap$chr), # Add "chr" prefix for UCSC compatibility
  chromStart = cd@design@baitmap$start,
  chromEnd = cd@design@baitmap$end,
  name = cd@design@baitmap$bait_name,
  score = 100,       # Dummy score (0-1000)
  strand = ".",      # Dummy strand
  signalValue = 0,   # Dummy signal value
  pValue = -1,       # Dummy p-value (-log10)
  qValue = -1,       # Dummy q-value (-log10)
  peak = -1          # Dummy peak offset
)
write.table(narrowPeak_df, "spp.wgEncodeBroadHistoneGm12878CtcfStdAln_chr20and21.narrowPeak",
            sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)