# Load the gwascat package, which is critical for this workflow.
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("gwascat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(gwascat)

# --- Data preparation for a GRanges object (suitable for .rds files) ---
# This section reproduces the vignette's code to create the 'adgr' object,
# which is a gwasloc instance (extending GRanges) representing a subset
# of the GWAS catalog. This is a common Bioconductor S4 object type.
data(ebicat_2020_04_30)
adinds <- grep("autoimmu", ebicat_2020_04_30$MAPPED_TRAIT)
adgr <- ebicat_2020_04_30[adinds]

# --- Data preparation for a data.frame object (suitable for .csv files) ---
# This section reproduces the vignette's code to create the 'limdf' object,
# which is a data.frame derived from the EFO graph.