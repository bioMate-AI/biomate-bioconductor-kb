# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CSSQ")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CSSQ)

# Get the paths to the example data files within the CSSQ package
regionBed_path <- system.file("extdata", "chr19_regions.bed", package="CSSQ", mustWork = TRUE)
sampleInfo_path <- system.file("extdata", "sample_info.txt", package="CSSQ", mustWork = TRUE)
sampleCountData_path <- system.file("extdata", "sample_count_data.txt", package="CSSQ", mustWork = TRUE)

# Read the data into R objects, exactly as the vignette does for its internal use
# chr19_regions.bed is read without explicit sep/header, implying whitespace sep and no header
regionBed_data <- read.table(regionBed_path)

# sample_info.txt is read with tab separator and header
sampleInfo_data <- read.table(sampleInfo_path, sep = "\t", header = TRUE)

# sample_count_data.txt is described as tab-separated in the vignette, and loadCountData
# expects it in that format. We read it here to get its content for writing.
sampleCountData_data <- read.table(sampleCountData_path, sep = "\t", header = TRUE)

# Write the R objects to the specified input files in the working directory,
# matching the format expected by the workflow's read operations.

# Write sample_info.txt: tab-separated, with header, no row names, no quotes
write.table(sampleInfo_data, "sample_info.txt", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)

# Write chr19_regions.bed: space-separated, no header, no row names, no quotes
write.table(regionBed_data, "chr19_regions.bed", sep = " ", row.names = FALSE, col.names = FALSE, quote = FALSE)

# Write sample_count_data.txt: tab-separated, with header, no row names, no quotes
write.table(sampleCountData_data, "sample_count_data.txt", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE)