# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HDCytoData", "CytoMDS", "flowCore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(HDCytoData))
library(CytoMDS)
library(flowCore) # Explicitly load flowCore for flowFrame/flowSet manipulation

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
BCRXL_fs <- HDCytoData::Bodenmiller_BCR_XL_flowSet()

phenoData <- flowCore::pData(BCRXL_fs)
additionalPhenoData <- flowCore::keyword(BCRXL_fs[[1]], "EXPERIMENT_INFO")$EXPERIMENT_INFO
phenoData <- cbind(phenoData, additionalPhenoData)
flowCore::pData(BCRXL_fs) <- phenoData

markerInfo <- flowCore::keyword(BCRXL_fs[[1]], "MARKER_INFO")$MARKER_INFO
chClass <- markerInfo$marker_class
chLabels <- markerInfo$channel_name[chClass != "none"]
chMarkers <- markerInfo$marker_name[chClass != "none"] # This object is created by the vignette but not directly saved as an input file.

trans <- flowCore::arcsinhTransform( transformationId="ArcsinhTransform", a = 0, b = 1/5, c = 0)
BCRXL_fs_trans <- flowCore::transform( BCRXL_fs, flowCore::transformList(chLabels, trans))

# 2. Serialize that object to EACH declared input file (fileNames)
# The workflow reads 'fileNames.rds' which contains a vector of paths to individual flowFrame .rds files.

# Get sample names from the flowSet to use as base names for individual flowFrame files
sample_names <- flowCore::sampleNames(BCRXL_fs_trans)

# Initialize a character vector to store the paths of the saved flowFrame files
fileNames <- character(length(BCRXL_fs_trans))

# Save each flowFrame from the flowSet to an individual .rds file
for (i in seq_along(BCRXL_fs_trans)) {
    # Construct a unique file name for each flowFrame
    ff_filename <- paste0("flowFrame_", sample_names[i], ".rds")
    
    # Save the i-th flowFrame object
    saveRDS(BCRXL_fs_trans[[i]], file = ff_filename)
    
    # Store the generated file name in the fileNames vector
    fileNames[i] <- ff_filename
}

# Save the 'fileNames' vector itself to "fileNames.rds"
saveRDS(fileNames, file = "fileNames.rds")