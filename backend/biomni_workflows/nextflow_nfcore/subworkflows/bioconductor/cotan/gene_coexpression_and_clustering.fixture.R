# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("COTAN", "zeallot")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(COTAN)
library(zeallot)
conflicted::conflict_prefer("%<-%", "zeallot")
prevOptState <- options(parallelly.fork.enable = TRUE)

# The vignette downloads "GSM2861514_E175_All_Cells_DGE.txt.gz" using GEOquery.
# To fulfill the "MUST run fully OFFLINE" constraint and "Use ONLY data shipped in installed packages",
# we assume this file is available in the 'extdata' directory of the 'COTAN' package.
datasetFileName <- system.file("extdata", "GSM2861514_E175_All_Cells_DGE.txt.gz", package = "COTAN")

# Verify the file exists for offline reproducibility
if (!file.exists(datasetFileName)) {
  stop("Required dataset file 'GSM2861514_E175_All_Cells_DGE.txt.gz' not found in COTAN package 'extdata'.")
}

rawDataset <- read.csv(datasetFileName, sep = "\t", row.names = 1L)

# Create the COTAN object
cond <- "mouse_cortex_E17.5"
GEO <- "GSM2861514" # Keep the GEO accession string as metadata
obj <- COTAN(raw = rawDataset)
obj <- initializeMetaDataset(
  obj,
  GEO = GEO,
  sequencingMethod = "Drop_seq",
  sampleCondition = cond
)

# Assign to each cell its origin
data(vignette.cells.origin)
obj <- addCondition(obj, condName = "origin", conditions = vignette.cells.origin)
rm(vignette.cells.origin)

# Data cleaning steps (copied verbatim from vignette, omitting plot calls that don't modify 'obj')

# Drop cells with too many reads
cellsSizeThr <- 6