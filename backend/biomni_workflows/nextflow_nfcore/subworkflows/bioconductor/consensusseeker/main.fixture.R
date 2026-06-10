# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("consensusSeekeR", "Seqinfo", "rtracklayer", "GenomicRanges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(consensusSeekeR)
library(Seqinfo)
library(rtracklayer)
library(GenomicRanges)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# For file_narrowPeak:
# The workflow expects a file named "file_narrowPeak" in the working directory.
# The vignette provides a path to an example narrowPeak file within the package.
file_narrowPeak_source <- system.file("extdata", "A549_FOSL2_ENCSR000BQO_MZW_part_chr_1_and_12.narrowPeak", package = "consensusSeekeR")

# For chrList:
# The workflow expects a Seqinfo object. The vignette shows how to create one.
# Using the hg19 subset example from the vignette.
hg19Info <- Seqinfo(genome="hg19")
chrList <- hg19Info[c("chr1", "chr10", "chrX")]

# 2. Serialize objects to EACH declared input file

# Copy the example narrowPeak file to the working directory with the expected name.
file.copy(file_narrowPeak_source, "file_narrowPeak", overwrite = TRUE)

# Save the chrList Seqinfo object as an RDS file.
saveRDS(chrList, "chrList.rds")