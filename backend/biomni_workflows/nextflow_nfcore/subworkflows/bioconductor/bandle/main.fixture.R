# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bandle", "pRolocdata", "pRoloc")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("bandle")
library("pRolocdata")
library("pRoloc") # Required for plot2D and setStockcol, implicitly used by vignette

# Reproduce data preparation from the vignette
data("tan2009r1")

# Set stock colours (for plotting, but included for exact reproduction)
setStockcol(NULL)
setStockcol(paste0(getStockcol(), "90"))

# Simulate a differential localisation experiment
set.seed(1)
tansim <- sim_dynamic(object = tan2009r1, numRep = 6L, numDyn = 100L)

# Split the datasets into two separate lists, one for control and one for treatment
control <- tansim$lopitrep[1:3]
treatment <- tansim$lopitrep[4:6]

# Serialize the objects to RData files
save(control, file = "control_replicates.RData")
save(treatment, file = "treatment_replicates.RData")