# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNVRanger", "GenomicRanges", "RaggedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNVRanger)
library(GenomicRanges)
library(RaggedExperiment)

# Reproduce the vignette's data-preparation code to materialize the example objects.

# 1. Read the input CSV from the package's extdata
data.dir <- system.file("extdata", package="CNVRanger")
call.file <- file.path(data.dir, "Silva16_PONE_CNV_calls.csv")
calls <- read.csv(call.file, as.is=TRUE)

# 2. Serialize the 'calls' data frame to Silva16_PONE_CNV_calls.csv in the working directory
write.csv(calls, "Silva16_PONE_CNV_calls.csv", row.names=FALSE)

# 3. Create the GRangesList object 'grl' as shown in the vignette
grl <- GenomicRanges::makeGRangesListFromDataFrame(calls, split.field="NE_id", keep.extra.columns=TRUE)
grl <- GenomicRanges::sort(grl)

# 4. Create the RaggedExperiment object 'ra' as shown in the vignette
ra <- RaggedExperiment::RaggedExperiment(grl)
weight <- rnorm(ncol(ra), mean=1100, sd=100)
fcr <- rnorm(ncol(ra), mean=6, sd=1.5)
RaggedExperiment::colData(ra)$weight <- round(weight, digits=2)
RaggedExperiment::colData(ra)$fcr <- round(fcr, digits=2)

# Note: The provided vignette does not contain any code or instructions for creating
# or using an 'EnsDb' object. Adhering to the critical constraint to "NEVER reference
# a package/object the documented code does not use" and "Use ONLY data shipped in
# installed packages", no EnsDb object or file is generated.