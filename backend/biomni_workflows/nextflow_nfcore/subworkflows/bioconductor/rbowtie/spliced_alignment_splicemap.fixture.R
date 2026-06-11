# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Rbowtie")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Rbowtie)

# Prepare the reference index directory ('refDir')
# The vignette uses system.file to locate sample reference FASTA files.
# It then builds an index into a temporary directory.
# We will build the index into a directory named 'refDir' in the current working directory.

# Get the paths to the sample reference FASTA files as shown in the vignette
refFiles <- dir(system.file(package="Rbowtie", "samples", "refs"), full=TRUE)

# Define the output directory for the bowtie index, named 'refDir'
output_index_dir <- "refDir"
if (!dir.exists(output_index_dir)) {
  dir.create(output_index_dir, recursive = TRUE)
}

# Build the bowtie index
# The vignette uses prefix="index" and force=TRUE. We will use the same.
bowtie_build_output <- Rbowtie::bowtie_build(references = refFiles,
                                             outdir = output_index_dir,
                                             prefix = "index",
                                             force = TRUE)

# The 'refDir' directory now contains the bowtie index files (e.g., index.1.ebwt, index.rev.1.ebwt, etc.).

# Address 'readsFiles'
# The vignette provides no code to generate or load 'readsFiles'.
# The prompt explicitly forbids inventing data or using random data,
# and requires reproducing the VIGNETTE'S OWN data-preparation code.
# Since the vignette does not contain data-preparation code for 'readsFiles',
# it is impossible to fulfill this requirement for 'readsFiles'.
# Therefore, 'readsFiles' will not be created by this script.