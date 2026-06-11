library(ENmix)
library(minfiData)

# 1. rgSet: Read raw idat files from minfiData
path <- file.path(find.package("minfiData"), "extdata")
rgSet <- readidat(path = path, recursive = TRUE)
saveRDS(rgSet, "rgSet.rds")

# 2. mdat: Preprocess the data (background correction, dye bias correction, normalization)
qc <- QCinfo(rgSet, detPtype="negative", detPthre=0.000001)
mdat <- preprocessENmix(rgSet, bgParaEst="oob", dyeCorr="RELIC", QCinfo=qc, nCores=1)
mdat <- norm.quantile(mdat, method="quantile1")
saveRDS(mdat, "mdat.rds")

# 3. beta: Probe-type bias adjustment and quality control filtering
beta <- rcp(mdat, qcscore=qc)
beta <- qcfilter(beta, qcscore=qc, rmcr=TRUE, rthre=0.05, cthre=0.05, impute=TRUE)
saveRDS(beta, "beta.rds")

# 4. pheno: Create phenotype data frame matching the samples
pheno <- data.frame(
    SampleID = colnames(beta),
    Age = c(23, 45, 52, 36, 58, 43),
    Female = c(1, 0, 1, 1, 0, 1)
)
saveRDS(pheno, "pheno.rds")

# 5. dat: Simulate a BED-formatted data frame of association P-values for DMR analysis
dat <- simubed()
saveRDS(dat, "dat.rds")