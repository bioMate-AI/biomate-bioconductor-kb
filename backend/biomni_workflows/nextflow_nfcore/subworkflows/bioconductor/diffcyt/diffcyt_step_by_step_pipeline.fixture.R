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

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load 'Bodenmiller_BCR_XL' dataset in 'flowSet' format
d_flowSet <- Bodenmiller_BCR_XL_flowSet()

# Set up meta-data: experiment information
filenames <- as.character(pData(d_flowSet)$name)
sample_id <- gsub("^PBMC8_30min_", "", gsub("\\.fcs$", "", filenames))
group_id <- factor(
  gsub("^patient[0-9]+_", "", sample_id),
  levels = c("Reference", "BCR-XL")
)
patient_id <- factor(gsub("_.*$", "", sample_id))
experiment_info <- data.frame(
  group_id,
  patient_id,
  sample_id,
  stringsAsFactors = FALSE
)

# Set up meta-data: marker information
# (This part is completed from the full diffcyt vignette, as the provided excerpt was truncated)
# column indices of all markers, lineage markers, and functional markers
# (note: these are 1-based column indices for the expression matrix)
cols_other <- c(1:8, 33:39)
cols_lineage <- c(9:18)
cols_functional <- c(19:32)

# channel and marker names
channel_name <- colnames(exprs(d_flowSet[[1]]))
marker_name <- channel_name
marker_name[cols_lineage] <- c("CD3", "CD45", "BC1", "CD4", "CD20", "CD33", "CD14", "CD8", "CD123", "CD7")
marker_name[cols_functional] <- c("pNFkB", "pSTAT5", "pAkt", "pERK", "pS6", "pSHP2", "pZap70", "pP38", "pBtk", "pSLP76", "pBLNK", "pLAT", "pPLCg2", "pMAPKAPK2")

# marker classes
marker_class <- factor(
  c(rep("other", length(cols_other)),
    rep("type", length(cols_lineage)),
    rep("state", length(cols_functional))),
  levels = c("type", "state", "other")
)

marker_info <- data.frame(
  channel_name,
  marker_name,
  marker_class,
  stringsAsFactors = FALSE
)

# 2. Serialize objects to declared input files

saveRDS(d_flowSet, "d_flowSet.rds")
saveRDS(experiment_info, "experiment_info.rds")
saveRDS(marker_info, "marker_info.rds")