# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RnBeads", "RnBeads.hg19")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(RnBeads))
suppressPackageStartupMessages(library(RnBeads.hg19))

# Reproduce the vignette's data-preparation code to materialize the example object
# The vignette uses data(small.example.object) from RnBeads.hg19
data(small.example.object)

# The object created is rnb.set.example, which is an RnBSet object.

# 1. Serialize the sample annotation to 'sample_annotation.csv'
# The sample annotation is accessed via pheno(rnb.set.example)
sample_annotation_df <- pheno(rnb.set.example)
write.csv(sample_annotation_df, "sample_annotation.csv", row.names = FALSE)

# 2. Serialize the RnBSet object to 'idat.rds'
# The workflow expects 'idat' files (typically a directory of binary files).
# Since generating actual idat files from an RnBSet object or an offline source
# is not feasible and not shown in the vignette, and the prompt allows
# 'saveRDS for an S4 object', we will save the RnBSet object itself.
# This file will represent the data that would have been read from the 'idat' input.
saveRDS(rnb.set.example, "idat.rds")