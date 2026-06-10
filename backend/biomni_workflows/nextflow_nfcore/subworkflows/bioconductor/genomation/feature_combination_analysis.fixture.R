# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("genomation", "genomationData", "rtracklayer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(genomation)
library(genomationData)
library(rtracklayer) # Required for writing GRanges objects to broadPeak format

# Define source file paths from the genomationData package's extdata directory.
# These are the exact files referenced in the genomation vignette for broadPeak and BAM data.

# Source for tf_peaks_1.broadPeak (gzipped broadPeak file)
source_broadPeak1_gz <- system.file(
  "extdata",
  "wgEncodeBroadHistoneH1hescCtcfStdPk.broadPeak.gz",
  package = "genomationData"
)

# Source for tf_peaks_2.broadPeak (another gzipped broadPeak file)
source_broadPeak2_gz <- system.file(
  "extdata",
  "wgEncodeBroadHistoneH1hescP300kat3bPk.broadPeak.gz",
  package = "genomationData"
)

# Source for aligned_reads.bam (BAM alignment file)
source_bam <- system.file(
  "extdata",
  "wgEncodeBroadHistoneH1hescCtcfStdAlnRep1.chr21.bam",
  package = "genomationData"
)

# Source for the companion .bai index file for aligned_reads.bam
source_bam_bai <- system.file(
  "extdata",
  "wgEncodeBroadHistoneH1hescCtcfStdAlnRep1.chr21.bam.bai",
  package = "genomationData"
)

# 1. Create tf_peaks_1.broadPeak
# Read the gzipped broadPeak file into a GRanges object using genomation's specific reader.
tf_peaks_1_gr <- readBroadPeak(source_broadPeak1_gz)
# Write the GRanges object to an uncompressed broadPeak file.
# rtracklayer::export handles the broadPeak format correctly, preserving all columns.
export(tf_peaks_1_gr, "tf_peaks_1.broadPeak")

# 2. Create tf_peaks_2.broadPeak
# Read the second gzipped broadPeak file into a GRanges object.
tf_peaks_2_gr <- readBroadPeak(source_broadPeak2_gz)
# Write the GRanges object to an uncompressed broadPeak file.
export(tf_peaks_2_gr, "tf_peaks_2.broadPeak")

# 3. Create aligned_reads.bam
# Copy the source BAM file directly, as it's already in the correct binary format.
file.copy(source_bam, "aligned_reads.bam", overwrite = TRUE)

# For functional use of BAM files in Bioconductor workflows, a companion .bai index file
# is typically required for random access. Copy it as well.
file.copy(source_bam_bai, "aligned_reads.bam.bai", overwrite = TRUE)