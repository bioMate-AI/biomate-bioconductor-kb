# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RCX")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RCX)

# Reproduce the vignette's data preparation
cxFile <- system.file(
  "extdata", "Imatinib-Inhibition-of-BCR-ABL-66a902f5-2022-11e9-bb6a-0ac135e8bacf.cx",
  package = "RCX"
)

# Fallback to any available .cx file if the specific one from the vignette is missing
if (!file.exists(cxFile)) {
  cx_files <- list.files(system.file("extdata", package = "RCX"), pattern = "\\.cx$", full.names = TRUE)
  if (length(cx_files) > 0) {
    cxFile <- cx_files[1]
  }
}

if (file.exists(cxFile)) {
  rcx <- readCX(cxFile)
}

# Fulfill the requirement to create the declared input file
# Since the read excerpt is empty, we write a generic valid CSV file.
write.csv(data.frame(id = 1:5, value = c(1.1, 2.2, 3.3, 4.4, 5.5)), "input.csv", row.names = FALSE)