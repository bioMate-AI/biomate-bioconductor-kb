# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HDCytoData", "flowCore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(HDCytoData)
library(flowCore)

# Reproduce the vignette's data-preparation code for d_flowSet
# From section 4.2 "Load data from 'HDCytoData' package"
d_flowSet <- Bodenmiller_BCR_XL_flowSet()

# Reproduce the vignette's data-preparation code for experiment_info
# From section 4.4 "Set up meta-data"
filenames <- as.character(pData(d_flowSet)$name)
sample_id <- gsub("^PBMC8_30min_", "", gsub("\\.fcs$", "", filenames))
group_id <- factor(
  gsub("^patient[0-9]+_", "", sample_id),
  levels = c("Reference", "BCR-XL")
)
patient_id <- factor(gsub("_.*$", "", sample_id))
experiment_info <- data.frame(
  group_id, patient_id, sample_id, stringsAsFactors = FALSE
)

# The vignette code for 'marker_info' is truncated in the provided text.
# As per the instructions, I cannot invent or guess the code for 'marker_info'.
# Therefore, 'marker_info' cannot be generated from the provided vignette text.

# Serialize d_flowSet to d_flowSet.rds
saveRDS(d_flowSet, "d_flowSet.rds")

# Serialize experiment_info to experiment_info.rds
# The workflow reads either .rds or .csv. Using .rds to preserve R object structure.
saveRDS(experiment_info, "experiment_info.rds")