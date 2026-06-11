# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CleanUpRNAseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("CleanUpRNAseq")

# Define the source paths for the input files from the package's extdata
gtf_src <- system.file("extdata", "example.gtf.gz", package = "CleanUpRNAseq")
bam_src <- system.file("extdata", "K084CD7PCD1N.srt.bam", package = "CleanUpRNAseq")
# The vignette uses dir(in_dir, ".sf$", full.name = TRUE) to find quant.sf
# We can directly specify it as it's a known file in extdata.
quant_sf_src <- system.file("extdata", "quant.sf", package = "CleanUpRNAseq")
col_data_src <- system.file("extdata", "example.colData.txt", package = "CleanUpRNAseq")

# Define the destination file names in the current working directory
gtf_dest <- "example.gtf.gz"
bam_dest <- "K084CD7PCD1N.srt.bam"
quant_sf_dest <- "quant.sf"
col_data_dest <- "example.colData.txt"

# Copy the files to the current working directory
file.copy(from = gtf_src, to = gtf_dest, overwrite = TRUE)
file.copy(from = bam_src, to = bam_dest, overwrite = TRUE)
file.copy(from = quant_sf_src, to = quant_sf_dest, overwrite = TRUE)
file.copy(from = col_data_src, to = col_data_dest, overwrite = TRUE)