# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HDCytoData", "CytoMDS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(HDCytoData)
library(CytoMDS)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load the flowSet version of the BodenMiller2012 dataset
BCRXL_fs <- HDCytoData::Bodenmiller_BCR_XL_flowSet()

# Prepare phenoData
phenoData <- flowCore::pData(BCRXL_fs)
additionalPhenoData <- flowCore::keyword(BCRXL_fs[[1]], "EXPERIMENT_INFO")$EXPERIMENT_INFO
phenoData <- cbind(phenoData, additionalPhenoData)
flowCore::pData(BCRXL_fs) <- phenoData

# Select channels/markers
markerInfo <- flowCore::keyword(BCRXL_fs[[1]], "MARKER_INFO")$MARKER_INFO
chClass <- markerInfo$marker_class
chLabels <- markerInfo$channel_name[chClass != "none"]

# Scale transformation
# Following the vignette's exact usage for arcsinhTransform and transformList (no flowCore:: prefix)
trans <- arcsinhTransform( transformationId="ArcsinhTransform", a = 0, b = 1/5, c = 0)
BCRXL_fs_trans <- transform( BCRXL_fs, transformList(chLabels, trans))

# 2. Serialize objects to declared input files

# exprMatrixList.rds should contain the transformed flowSet object
saveRDS(BCRXL_fs_trans, "exprMatrixList.rds")

# phenoDataExpr.csv should contain the prepared phenoData data frame
# The pData of BCRXL_fs_trans should be identical to the modified pData of BCRXL_fs.
phenoDataExpr <- flowCore::pData(BCRXL_fs_trans)
write.csv(phenoDataExpr, "phenoDataExpr.csv", row.names = FALSE)