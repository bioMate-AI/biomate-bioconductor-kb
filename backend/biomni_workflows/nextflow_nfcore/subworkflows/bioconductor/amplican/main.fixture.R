# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("amplican")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(amplican)

# Define the names of the output files/folders as expected by the workflow
output_config_file <- "config.csv"
output_fastq_folder <- "fastq_folder"

# Get the path to the example config.csv file within the amplican package
source_config_path <- system.file("extdata", "config.csv", package = "amplican")

# Get the path to the extdata folder containing the example fastq files
source_extdata_folder <- system.file("extdata", package = "amplican")

# Create the output fastq_folder directory if it doesn't exist
if (!dir.exists(output_fastq_folder)) {
  dir.create(output_fastq_folder)
}

# Copy the example config.csv to the current working directory
file.copy(source_config_path, output_config_file, overwrite = TRUE)

# Define the specific fastq files to copy based on the vignette's config example
fastq_files_to_copy <- c(
  "R1_001.fastq",
  "R2_001.fastq",
  "R1_002.fastq",
  "R2_002.fastq"
)

# Copy each required fastq file from the package's extdata to the output_fastq_folder
for (fastq_file in fastq_files_to_copy) {
  source_fastq_path <- file.path(source_extdata_folder, fastq_file)
  destination_fastq_path <- file.path(output_fastq_folder, fastq_file)
  file.copy(source_fastq_path, destination_fastq_path, overwrite = TRUE)
}