# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DAMEfinder", "SummarizedExperiment", "GenomicRanges", "BSgenome.Hsapiens.UCSC.hg19", "Biostrings")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library(DAMEfinder)
  library(SummarizedExperiment)
  library(GenomicRanges)
  library(BSgenome.Hsapiens.UCSC.hg19)
  library(Biostrings)
})

# 1. Reproduce the vignette's data-preparation code to materialize the example objects.

# Get paths to example BAM and VCF files from the DAMEfinder package.
# The problem specifies single input files: bam.file, vcf.file.
# We use the first example file for each type from the vignette's lists.
example_bam_source_path <- system.file("extdata", "NORM1_chr19_trim.bam", package = "DAMEfinder")
example_vcf_source_path <- system.file("extdata", "NORM1.chr19.trim.vcf", package = "DAMEfinder")

# Create the reference_file DNAStringSet object as shown in the vignette.
genome <- BSgenome.Hsapiens.UCSC.hg19
seqnames(genome) <- gsub("chr","",seqnames(genome))
reference_file_obj <- DNAStringSet(genome[[19]], use.names = TRUE)
names(reference_file_obj) <- 19

# 2. Serialize that object to EACH declared input file in the EXACT format the workflow reads.

# For 'bam.file': Copy the example BAM file to the working directory.
file.copy(from = example_bam_source_path, to = "bam.file", overwrite = TRUE)

# For 'vcf.file': Copy the example VCF file to the working directory.
file.copy(from = example_vcf_source_path, to = "vcf.file", overwrite = TRUE)

# For 'reference_file': Write the DNAStringSet object to a FASTA file,
# which can be read by Biostrings::readDNAStringSet.
writeXStringSet(reference_file_obj, "reference_file")