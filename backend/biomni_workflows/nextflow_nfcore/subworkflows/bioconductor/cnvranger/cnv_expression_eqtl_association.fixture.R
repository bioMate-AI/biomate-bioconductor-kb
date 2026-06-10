# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNVRanger")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNVRanger)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code for CNV calls
# The vignette reads 'Silva16_PONE_CNV_calls.csv' from the package's 'extdata' directory.
# We will read this internal file and then write it to the current working directory
# under the specified input file name.
cnv_data_dir <- system.file("extdata", package="CNVRanger")
cnv_call_file_source <- file.path(cnv_data_dir, "Silva16_PONE_CNV_calls.csv")
calls <- read.csv(cnv_call_file_source, as.is=TRUE)

# 2. Serialize the 'calls' object to the declared input file: Silva16_PONE_CNV_calls.csv
# Matching the format implied by read.csv (comma-separated, no row names in output).
write.csv(calls, file="Silva16_PONE_CNV_calls.csv", row.names=FALSE)

# 3. Reproduce the VIGNETTE'S OWN data-preparation code for RNA-seq counts
# The vignette uses 'Silva16_PONE_RNAseq_counts.txt' for RNA-seq counts.
# We will use this content for the requested 'counts_cleaned.txt'.
rna_seq_count_file_source <- file.path(cnv_data_dir, "Silva16_PONE_RNAseq_counts.txt")
counts <- read.delim(rna_seq_count_file_source, row.names=1)

# 4. Serialize the 'counts' object to the declared input file: counts_cleaned.txt
# Matching the format implied by read.delim (tab-separated, first column as row names, no quotes).
write.table(counts, file="counts_cleaned.txt", sep="\t", quote=FALSE, row.names=TRUE)