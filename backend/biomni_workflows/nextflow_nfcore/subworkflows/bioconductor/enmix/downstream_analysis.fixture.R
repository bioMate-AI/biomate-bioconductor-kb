library(ENmix)
library(minfiData)

# Read in raw idat files from minfiData
path <- file.path(find.package("minfiData"), "extdata")
rgSet <- readidat(path = path, recursive = TRUE)

# Generate quality control (QC) information
qc <- QCinfo(rgSet)

# Background correction and dye bias correction
mdat <- preprocessENmix(rgSet, bgParaEst="oob", dyeCorr="RELIC", QCinfo=qc, nCores=1)

# Between-array normalization
mdat <- norm.quantile(mdat, method="quantile1")

# Probe-type bias adjustment
beta <- rcp(mdat, qcscore=qc)

# Serialize objects to the working directory
saveRDS(rgSet, "rgSet")
saveRDS(mdat, "mdat")
saveRDS(beta, "beta")