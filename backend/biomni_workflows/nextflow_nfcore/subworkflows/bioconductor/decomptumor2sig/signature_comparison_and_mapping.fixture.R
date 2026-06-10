# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("decompTumor2Sig")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(decompTumor2Sig)

# 1. Prepare Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv
# The vignette states: "Among its examples, the decompTumor2Sig package provides a small set of four Shiraishi-type signatures in flat files."
# The data preparation for this input file is to locate the example file provided by the package.
shiraishi_source_path <- system.file("extdata", "Nik-Zainal_PMID_22608084-pmsignature-sig1.tsv", package="decompTumor2Sig")

# Serialize the content of this example file to the declared input file.
# Since