# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("APAlyzer", "TBX20BamSubset", "Rsamtools")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressMessages(library("APAlyzer"))
suppressMessages(library("TBX20BamSubset"))
suppressMessages(library("Rsamtools"))

# 1. Reproduce the VIGNETTE'S OWN data-preparation code for 'flsall'
# This creates a BamFileList object pointing to example BAM files.
flsall = getBamFileList()

# 2. Serialize 'flsall' to the working directory.
# 'flsall' is an S4 object (BamFileList), so saveRDS is appropriate for serialization.
saveRDS(flsall, file="flsall")

# 3. Reproduce the VIGNETTE'S OWN data-preparation code for objects in 'mm9_REF.RData'.
# The vignette shows downloading 'mm9_REF.RData' from a URL.
# However, the 'apalyzer' package itself ships this file in its 'extdata' directory,
# which satisfies the "MUST run fully OFFLINE" and "Use ONLY data shipped in installed packages"
# constraints.
# Load the objects (refUTRraw, dfIPA, dfLE) from the package's extdata.
mm9_ref_path = system.file("extdata", "mm9_REF.RData", package="APAlyzer")
load(mm9_ref_path) # This loads refUTRraw, dfIPA, dfLE into the current environment.

# 4. Serialize these objects (refUTRraw, dfIPA, dfLE) to 'mm9_REF.RData' in the working directory.
# The original file is an .RData file, so save() is appropriate to recreate it.
save(refUTRraw, dfIPA, dfLE, file="mm9_REF.RData")