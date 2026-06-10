library(DFP)
library(Biobase)

dataDir <- system.file("extdata", package="DFP")
fileExprs <- file.path(dataDir, "exprsData.csv")
filePhenodata <- file.path(dataDir, "pData.csv")

if (file.exists(fileExprs) && file.exists(filePhenodata)) {
    file.copy(fileExprs, "exprsData.csv", overwrite = TRUE)
    file.copy(filePhenodata, "pData.csv", overwrite = TRUE)
} else {
    data(rmadataset, package="DFP")
    
    # Construct the expression data CSV
    write.csv(exprs(rmadataset), file="exprsData.csv", quote=FALSE)
    
    # Construct the phenotype data CSV
    write.csv(pData(rmadataset), file="pData.csv", quote=FALSE)
}