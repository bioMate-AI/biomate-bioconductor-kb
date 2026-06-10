# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("consensusSeekeR", "GenomicRanges", "rtracklayer", "Seqinfo")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(consensusSeekeR)
library(GenomicRanges)
library(rtracklayer)
library(Seqinfo)

# 1. Reproduce data-preparation code from the vignette

# Create chrList object as shown in section 5.2 "Chromosomes information"
chrList <- Seqinfo(seqnames=c("chr1", "chr2", "chr3"), seqlengths=c(1000, 2000, 1500), isCircular=c(FALSE, FALSE, FALSE), genome="BioconductorAlien")

# Load example NarrowPeak file and extract peaks and regions
# as shown in section 6 "Read NarrowPeak files"
file_narrowPeak <- system.file("extdata", "A549_FOSL2_ENCSR000BQO_MZW_part_chr_1_and_12.narrowPeak", package = "consensusSeekeR")
result <- readNarrowPeakFile(file_narrowPeak, extractRegions = TRUE, extractPeaks = TRUE)

# The workflow expects three sets of nucleosome positions and ranges
# (NOrMAL, PING, NucPosSimulator). The vignette provides only one example
# of how to generate GRanges objects for peaks and regions from a NarrowPeak file.
# Following the strict instruction to "NEVER invent a dataset name, NEVER use random data,
# NEVER guess", we will use the single example data generated from the vignette
# for all required nucleosome position and range inputs.

# Assign the extracted peaks and regions to the required workflow variables
# NOrMAL data
NOrMAL_nucleosome_positions <- result$peak
NOrMAL_nucleosome_ranges <- result$narrowPeak

# PING data (using the same example data as no other is provided in the vignette)
PING_nucleosome_positions <- result$peak
PING_nucle