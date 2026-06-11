# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HDCytoData", "CytoMDS", "ggplot2", "patchwork", "flowCore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(HDCytoData))
library(CytoMDS)
library(ggplot2)
library(patchwork)
library(flowCore) # Explicitly load flowCore for pData, keyword, etc.

# Reproduce vignette's data preparation code
BCRXL_fs <- HDCytoData::Bodenmiller_BCR_XL_flowSet()

phenoData <- flowCore::pData(BCRXL_fs)
additionalPhenoData <- keyword(BCRXL_fs[[1]], "EXPERIMENT_INFO")$EXPERIMENT_INFO
phenoData <- cbind(phenoData, additionalPhenoData)
flowCore::pData(BCRXL_fs) <- phenoData

markerInfo <- keyword(BCRXL_fs[[1]], "MARKER_INFO")$MARKER_INFO
chClass <- markerInfo$marker_class
chLabels <- markerInfo$channel_name[chClass != "none"]
chMarkers <- markerInfo$marker_name[chClass != "none"]

trans <- arcsinhTransform( transformationId="ArcsinhTransform", a = 0, b = 1/5, c = 0)
BCRXL_fs_trans <- transform( BCRXL_fs, transformList(chLabels, trans))

# Serialize objects to the exact file names and format the workflow reads
saveRDS(BCRXL_fs_trans, "BCRXL_fs_trans.rds")
saveRDS(phenoData, "phenoData.rds")