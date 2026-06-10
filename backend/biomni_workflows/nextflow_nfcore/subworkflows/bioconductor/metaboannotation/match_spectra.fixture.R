# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MetaboAnnotation")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MetaboAnnotation)

# Find and copy PestMix1_DDA.mzML
mzml_files <- list.files(system.file(package = "MetaboAnnotation"), pattern = "PestMix1_DDA\\.mzML$", recursive = TRUE, full.names = TRUE)
if (length(mzml_files) == 0 && requireNamespace("msdata", quietly = TRUE)) {
    mzml_files <- list.files(system.file(package = "msdata"), pattern = "PestMix1_DDA\\.mzML$", recursive = TRUE, full.names = TRUE)
}

if (length(mzml_files) > 0) {
    file.copy(mzml_files[1], "PestMix1_DDA.mzML", overwrite = TRUE)
} else {
    # Fallback synthetic mzML if not found
    writeLines('<?xml version="1.0" encoding="utf-8"?><mzML xmlns="http://psi.hupo.org/ms/mzml" version="1.1.0"></mzML>', "PestMix1_DDA.mzML")
}

# Find and copy minimb.RData
rdata_files <- list.files(system.file(package = "MetaboAnnotation"), pattern = "minimb\\.RData$", recursive = TRUE, full.names = TRUE)
if (length(rdata_files) == 0 && requireNamespace("msdata", quietly = TRUE)) {
    rdata_files <- list.files(system.file(package = "msdata"), pattern = "minimb\\.RData$", recursive = TRUE, full.names = TRUE)
}

if (length(rdata_files) > 0) {
    file.copy(rdata_files[1], "minimb.RData", overwrite = TRUE)
} else {
    # Fallback synthetic RData if not found
    minimb <- list()
    save(minimb, file = "minimb.RData")
}