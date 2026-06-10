# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CSSQ")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CSSQ)

# Get the path to the extdata directory of the CSSQ package
extdata_dir <- system.file("extdata", package = "CSSQ", mustWork = TRUE)

# 1. Reproduce chr19_regions.bed
# The workflow reads this file from the working directory.
# We copy the example file from the package's extdata to the current working directory.
file.copy(
    from = file.path(extdata_dir, "chr19_regions.bed"),
    to = "chr19_regions.bed",
    overwrite = TRUE
)

# 2. Reproduce sample_info.txt
# The workflow reads this file from the working directory.
# We copy the example file from the package's extdata to the current working directory.
file.copy(
    from = file.path(extdata_dir, "sample_info.txt"),
    to = "sample_info.txt",
    overwrite = TRUE
)

# 3. Reproduce BAM files
# The workflow implicitly reads BAM files, whose names are listed in sample_info.txt.
# We first read the sample_info.txt to get the names of the BAM files.
sampleInfo <- read.table(file.path(extdata_dir, "sample_info.txt"), sep = "\t", header = TRUE)

# Extract unique BAM file names from the 'IP' and 'IN' columns
bam_files_ip <- as.character(sampleInfo$IP)
bam_files_in <- as.character(sampleInfo$IN)
all_bam_files <- unique(c(bam_files_ip, bam_files_in))

# Copy each identified BAM file from the package's extdata to the current working directory.
for (bam_file_name in all_bam_files) {
    file.copy(
        from = file.path(extdata_dir, bam_file_name),
        to = bam_file_name,
        overwrite = TRUE
    )
}