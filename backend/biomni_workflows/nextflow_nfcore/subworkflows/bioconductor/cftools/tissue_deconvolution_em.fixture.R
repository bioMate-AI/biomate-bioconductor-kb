# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cfTools", "utils")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cfTools)
library(utils) # For system.file

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Set up demo directory to access example data files within the package
demo.dir <- system.file("data", package="cfTools")

# --- Generate fragMeth (for cfDeconvolve.reads.txt.gz) ---
# This section follows the vignette's "3.1 Merge paired-end sequencing reads to fragment-level"
# The input is a sorted BED file.
PEReads <- file.path(demo.dir, "demo.sorted.bed.txt.gz")
fragInfo <- MergePEReads(PEReads)

# This section follows the vignette's "3.2 Merge methylation states of CpGs on two strands to fragment-level"
# The inputs are CpG_OT* and CpG_OB* files from bismark methylation extractor.
CpG_OT <- file.path(demo.dir, "CpG_OT_demo.txt.gz")
CpG_OB <- file.path(demo.dir, "CpG_OB_demo.txt.gz")
methInfo <- MergeCpGs(CpG_OT, CpG_OB)

# This section follows the vignette's "3.3 Generate fragment-level information about methylation states"
# It combines the outputs from MergePEReads and MergeCpGs.
fragMeth <- GenerateFragMeth(fragInfo, methInfo)

# --- Generate markerParam (for cfDeconvolve.markers.txt.gz) ---
# This section follows the vignette's "3.4 Generate the methylation pattern of markers"
# The inputs are methylation levels, sample types, and marker names.
methLevel <- read.table(file.path(demo.dir, "beta_matrix.txt.gz"), row.names=1, header = TRUE)
sampleTypes <- read.table(file.path(demo.dir, "sample_type.txt.gz"), row.names=1, header = TRUE)$sampleType
markerNames <- read.table(file.path(demo.dir, "marker_index.txt.gz"), row.names=1, header = TRUE)$markerIndex

markerParam <- GenerateMarkerParam(methLevel, sampleTypes, markerNames)

# 2. Serialize objects to EACH declared input file in the EXACT format the workflow reads

# Define the output file names as expected by the workflow
fragMethFile2 <- "cfDeconvolve.reads.txt.gz"
markerParamFile2 <- "cfDeconvolve.markers.txt.gz"

# Write fragMeth to cfDeconvolve.reads.txt.gz
# The workflow reads this file using read.csv(..., header=TRUE, sep="\t").
# Therefore, we write a tab-separated file with column names and no row names or quotes.
write.table(fragMeth, file = fragMethFile2, sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)

# Write markerParam to cfDeconvolve.markers.txt.gz
# The workflow reads this file using read.csv(..., header=TRUE, sep="\t").
# Therefore, we write a tab-separated file with column names and no row names or quotes.
write.table(markerParam, file = markerParamFile2, sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)