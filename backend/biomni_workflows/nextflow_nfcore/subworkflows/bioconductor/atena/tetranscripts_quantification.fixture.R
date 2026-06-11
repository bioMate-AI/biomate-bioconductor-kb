# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("atena", "BiocParallel", "TxDb.Dmelanogaster.UCSC.dm6.ensGene", "GenomicFeatures", "Rsamtools", "GenomicAlignments", "GenomicRanges", "GenomeInfoDb", "Biostrings")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(atena)
library(BiocParallel)
library(TxDb.Dmelanogaster.UCSC.dm6.ensGene)
library(GenomicFeatures) # For genes()
library(Rsamtools)
library(GenomicAlignments)
library(GenomicRanges)
library(GenomeInfoDb) # For seqinfo
library(Biostrings) # For DNAStringSet and PhredQuality

# 1. Reproduce the vignette's data-preparation code for TE annotations (rmskLTR)
# The vignette uses annotaTEs with OneCodeToFindThemAll to get processed TE annotations.
# We will use the 'teann' object generated in the vignette as the 'rmskLTR' input.