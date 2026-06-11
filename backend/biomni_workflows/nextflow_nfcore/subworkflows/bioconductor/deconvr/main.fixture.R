# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("deconvR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(deconvR)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# For HumanCellTypeMethAtlas
data("HumanCellTypeMethAtlas")

# For IlluminaMethEpicB5ProbeIDs
data("IlluminaMethEpicB5ProbeIDs")

# For WGBS_GRanges.rda
# The vignette loads this from system.file, so we replicate that to get the object.
load(system.file("extdata", "WGBS_GRanges.rda", package = "deconvR"))

# 2. Serialize the objects to the declared input files in the exact format

# Save HumanCellTypeMethAtlas
# The workflow's load_input function attempts load() after readRDS() fails.
# data() loads .rda files, so saving as .rda is consistent.
save(HumanCellTypeMethAtlas, file = "HumanCellTypeMethAtlas")

# Save IlluminaMethEpicB5ProbeIDs
# Similar to HumanCellTypeMethAtlas, save as .rda.
save(IlluminaMethEpicB5ProbeIDs, file = "IlluminaMethEpicB5ProbeIDs")

# Save WGBS_GRanges
# The workflow explicitly expects "WGBS_GRanges.rda" and the vignette loads it as such.
save(WGBS_GRanges, file = "WGBS_GRanges.rda")