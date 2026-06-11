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
  library(Biostrings) # For DNAStringSet
})

# Get the paths to the example BAM and VCF files from the DAMEfinder package
bam_files_orig_paths <- c(system.file("extdata", "NORM1_chr19_trim.bam", package = "DAMEfinder"),
                          system.file("extdata", "CRC1_chr19_trim.bam", package = "DAMEfinder"))
vcf_files_orig_paths <- c(system.file("extdata", "NORM1.chr19.trim.vcf", package = "DAMEfinder"),
                          system.file("extdata", "CRC1.chr19.trim.vcf", package = "DAMEfinder"))

# Copy the BAM and VCF files to the current working directory.
# The workflow expects these files to be present in the working directory
# with their original base names.
file.copy(bam_files_orig_paths[1], basename(bam_files_orig_paths[1]), overwrite = TRUE)
file.copy(bam_files_orig_paths[2], basename(bam_files_orig_paths[2]), overwrite = TRUE)
file.copy(vcf_files_orig_paths[1], basename(vcf_files_orig_paths[1]), overwrite = TRUE)
file.copy(vcf_files_orig_paths[2], basename(vcf_files_orig_paths[2]), overwrite = TRUE)

# Create the 'reference_file' object exactly as shown in the vignette.
# This object is a DNAStringSet.
genome <- BSgenome.Hsapiens.UCSC.hg19
seqnames(genome) <- gsub("chr","",seqnames(genome))
reference_file <- DNAStringSet(genome[[19]], use.names = TRUE)
names(reference_file) <- 19

# Serialize the 'reference_file' DNAStringSet object to a file named 'reference_file'
# in the working directory. Since it's an S4 object, saveRDS is the appropriate format.
saveRDS(reference_file, file = "reference_file")