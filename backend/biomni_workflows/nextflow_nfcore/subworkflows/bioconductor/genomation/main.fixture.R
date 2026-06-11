# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("genomation", "genomationData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(genomation)
library(genomationData) # Required for accessing example BAM files

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette uses system.file to locate example GTF and BAM files.

# For genomic_features.gtf:
# The vignette uses "extdata/chr21.refseq.hg19.gtf" from the genomation package.
gtf_source_path <- system.file("extdata/chr21.refseq.hg19.gtf", package = "genomation")

# For aligned_reads.bam:
# The vignette lists several BAM files in the genomationData package.
# We'll use "wgEncodeBroadHistoneH1hescCtcfStdAlnRep1.chr21.bam" as an example.
bam_source_path <- system.file("extdata/wgEncodeBroadHistoneH1hescCtcfStdAlnRep1.chr21.bam", package = "genomationData")
# BAM files typically require an accompanying index file (.bai).
bam_bai_source_path <- system.file("extdata/wgEncodeBroadHistoneH1hescCtcfStdAlnRep1.chr21.bam.bai", package = "genomationData")

# 2. Serialize that object to EACH declared input file
# For file-based inputs like BAM and GTF, serialization means copying the example files.

# Copy the GTF file
file.copy(from = gtf_source_path, to = "genomic_features.gtf", overwrite = TRUE)

# Copy the BAM file
file.copy(from = bam_source_path, to = "aligned_reads.bam", overwrite = TRUE)

# Copy the BAM index file
file.copy(from = bam_bai_source_path, to = "aligned_reads.bam.bai", overwrite = TRUE)