# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("piano", "biomaRt")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(piano)
library(biomaRt)

# 1. Reproduce data-preparation code from the vignette

# Get path to example data and setup files
dataPath <- system.file("extdata", package="piano")

# Load pre-normalized data
myArrayData <- loadMAdata(datadir=dataPath, 
                          dataNorm="norm_data.txt.gz", 
                          platform="yeast2")

# Run differential expression analysis to get p-values, fold changes, and t-values
pfc <- diffExp(myArrayData, contrasts=c("aerobic_Clim - anaerobic_Clim", 
                                        "aerobic_Nlim - anaerobic_Nlim"))

# Extract myPval for the specified contrast
myPval <- pfc$pValues["aerobic_Clim - anaerobic_Clim"]

# Extract myFC for the specified contrast
myFC <- pfc$foldChanges["aerobic_Clim - anaerobic_Clim"]

# Extract myTval for the specified contrast (inferred from diffExp output structure)
myTval <- pfc$tValues["aerobic_Clim - anaerobic_Clim"]

# Use biomaRt to create mapGO, as shown in the vignette (eval=FALSE chunk)
ensembl <- useMart("ENSEMBL_MART_ENSEMBL", dataset="scerevisiae_gene_ensembl" ,host="www.ensembl.org")
mapGO <- getBM(attributes=c('affy_yeast_2', 'name_1006'), 
               mart = ensembl)
# Remove blanks as per vignette
mapGO <- mapGO[mapGO[,2]!="",]

# 2. Serialize objects to declared input files in the exact format the workflow reads

# The workflow's load_file function attempts readRDS first, so saveRDS is the most robust choice.
saveRDS(mapGO, "mapGO")
saveRDS(myTval, "myTval")
saveRDS(myPval, "myPval")
saveRDS(myFC, "myFC")