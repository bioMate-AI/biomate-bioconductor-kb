# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scRepertoire")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressMessages(library(scRepertoire))

# Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette provides an example dataset named "contig_list"
# which is a list of data frames, each representing contig annotations
# for a single sample.
data("contig_list")

# The workflow reads a single input file named "b_contigs.csv"
# using `read.csv("b_contigs.csv")`.
# We will take the first data frame from the `contig_list`
# to serve as the content for `b_contigs.csv`.
# This simulates a single sample's contig data being provided as input.
BCR.contigs_fixture <- contig_list[[1]]

# Serialize the object to "b_contigs.csv" in the exact format
# (CSV, without row names, to match typical raw data files).
write.csv(BCR.contigs_fixture, "b_contigs.csv", row.names = FALSE)