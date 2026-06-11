# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Rbowtie")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Rbowtie)

# --- Data preparation for refFiles ---
# The vignette's data preparation for reference sequences involves
# getting paths to FASTA files shipped with the Rbowtie package.
# The workflow expects a single input file named "refFiles" in the working directory.
# For aligners like bowtie, a common practice is to concatenate multiple
# reference FASTA files into a single FASTA file if a single input file is expected.

# Get the full paths to the example reference FASTA files from the Rbowtie package.
ref_file_paths_in_package <- dir(system.file(package="Rbowtie", "samples", "refs"), full=TRUE)

# Read the content of all individual reference FASTA files and concatenate them.
ref_sequences_content <- character()
for (f_path in ref_file_paths_in_package) {
  ref_sequences_content <- c(ref_sequences_content, readLines(f_path))
}

# Write the concatenated reference sequences to the output file named "refFiles"
# in the current working directory. This file will contain the raw FASTA data.
writeLines(ref_sequences_content, "refFiles")

# --- Data preparation for readsFiles ---
# The vignette does not explicitly show how to generate or use 'readsFiles'
# for the 'bowtie' function, but the Rbowtie package includes example read data.
# The workflow expects a single input file named "readsFiles" in the working directory.
# This file will contain the raw FASTQ data for the reads.

# Get the full path to the example reads FASTQ file from the Rbowtie package.
reads_file_path_in_package <- system.file(package="Rbowtie", "samples", "reads", "reads.fastq")

# Read the content of the reads FASTQ file.
reads_sequences_content <- readLines(reads_file_path_in_package)

# Write the reads sequences to the output file named "readsFiles"
# in the current working directory. This file will contain the raw FASTQ data.
writeLines(reads_sequences_content, "readsFiles")