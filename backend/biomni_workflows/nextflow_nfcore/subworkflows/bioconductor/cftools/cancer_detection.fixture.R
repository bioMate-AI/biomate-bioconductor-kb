# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cfTools", "utils")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cfTools)
library(utils) # For file.path

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Locate the directory containing example data files within the cfTools package
demo.dir <- system.file("data", package = "cfTools")

# --- Generate fragMeth object (for CancerDetector.reads.txt.gz) ---
# Paths to the input files for fragment-level methylation information
PEReads <- file.path(demo.dir, "demo.sorted.bed.txt.gz")
CpG_OT <- file.path(demo.dir, "CpG_OT_demo.txt.gz")
CpG_OB <- file.path(demo.dir, "CpG_OB_demo.txt.gz")

# Merge paired-end sequencing reads to fragment-level
fragInfo <- MergePEReads(PEReads)

# Merge methylation states of CpGs on two strands to fragment-level
methInfo <- MergeCpGs(CpG_OT, CpG_OB)

# Combine fragment information and methylation states
fragMeth <- GenerateFragMeth(fragInfo, methInfo)

# --- Generate markerParam object (for CancerDetector.markers.txt.gz) ---
# Paths to the input files for marker parameters
methLevel_file <- file.path(demo.dir, "beta_matrix.txt.gz")
sampleTypes_file <- file.path(demo.dir, "sample_type.txt.gz")
markerNames_file <- file.path(demo.dir, "marker_index.txt.gz")

# Read methylation levels
methLevel <- read.table(methLevel_file, row.names = 1, header = TRUE)

# Read sample types
sampleTypes <- read.table(sampleTypes_file, row.names = 1, header = TRUE)$sampleType

# Read marker names
markerNames <- read.table(markerNames_file, row.names = 1, header = TRUE)$markerIndex

# Generate the methylation pattern of markers
markerParam <- GenerateMarkerParam(methLevel, sampleTypes, markerNames)

# 2. Serialize objects to EACH declared input file in the EXACT format the workflow reads

# Output file for fragment-level methylation data
fragMethFile <- "CancerDetector.reads.txt.gz"
# The workflow reads this with `sep = "\t", colClasses = "character"`.
# Ensure tab-separated, no quotes, no row names, and include column names.
write.table(fragMeth,
            file = gzfile(fragMethFile),
            sep = "\t",
            quote = FALSE,
            row.names = FALSE,
            col.names = TRUE)

# Output file for marker parameters
markerParamFile <- "CancerDetector.markers.txt.gz"
# The workflow reads this with `sep = "\t"`.
# Ensure tab-separated, no quotes, no row names, and include column names.
write.table(markerParam,
            file = gzfile(markerParamFile),
            sep = "\t",
            quote = FALSE,
            row.names = FALSE,
            col.names = TRUE)