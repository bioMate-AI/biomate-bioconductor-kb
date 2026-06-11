# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNVRanger", "GenomicRanges", "RaggedExperiment", "MultiAssayExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNVRanger)
library(GenomicRanges)
library(RaggedExperiment)
library(MultiAssayExperiment)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# Read CNV calls from the example file
data.dir <- system.file("extdata", package="CNVRanger")
call.file <- file.path(data.dir, "Silva16_PONE_CNV_calls.csv")
calls <- read.csv(call.file, as.is=TRUE)

# Convert to GRangesList
grl <- GenomicRanges::makeGRangesListFromDataFrame(calls, split.field="NE_id", keep.extra.columns=TRUE)
grl <- GenomicRanges::sort(grl)

# Convert to RaggedExperiment
ra <- RaggedExperiment::RaggedExperiment(grl)

# Add simulated colData as shown in the vignette
weight <- rnorm(ncol(ra), mean=1100, sd=100)
fcr <- rnorm(ncol(ra), mean=6, sd=1.5)
RaggedExperiment::colData(ra)$weight <- round(weight, digits=2)
RaggedExperiment::colData(ra)$fcr <- round(fcr, digits=2)

# 2. Create the MultiAssayExperiment object
# The vignette mentions "Application to TCGA data stored in a MultiAssayExperiment"
# but does not provide explicit code for its construction from the example data.
# We construct a MultiAssayExperiment containing the 'ra' (RaggedExperiment) object
# that was created using the vignette's data preparation code.
# The colData for the MultiAssayExperiment is taken directly from 'ra'.
mae_list <- ExperimentList(list(CNV = ra))
mae_colData <- RaggedExperiment::colData(ra)

mae <- MultiAssayExperiment(experiments = mae_list, colData = mae_colData)

# 3. Serialize the object to the declared input file
saveRDS(mae, "MultiAssayExperiment")