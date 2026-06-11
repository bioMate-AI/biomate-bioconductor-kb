# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("trackViewer")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(trackViewer)

# Get the path to the 'extdata' directory within the trackViewer package
extdata_dir <- system.file("extdata", package="trackViewer", mustWork=TRUE)

# Define the source paths for the specific example files used in the vignette
source_cpsf160_repA_minus_wig <- file.path(extdata_dir, "cpsf160.repA_-.wig")
source_cpsf160_repA_plus_wig <- file.path(extdata_dir, "cpsf160.repA_+.wig")
source_fox2_bed <- file.path(extdata_dir, "fox2.bed")

# Define the destination file names as required by the workflow
destination_file1_wig <- "file1.wig"
destination_file2_wig <- "file2.wig"
destination_file3_bed <- "file3.bed"

# Copy the vignette's example data files to the current working directory
# with the names expected by the workflow. This ensures the content and format
# are identical to what the vignette uses as its input.
file.copy(from = source_cpsf160_repA_minus_wig, to = destination_file1_wig, overwrite = TRUE)
file.copy(from = source_cpsf160_repA_plus_wig, to = destination_file2_wig, overwrite = TRUE)
file.copy(from = source_fox2_bed, to = destination_file3_bed, overwrite = TRUE)