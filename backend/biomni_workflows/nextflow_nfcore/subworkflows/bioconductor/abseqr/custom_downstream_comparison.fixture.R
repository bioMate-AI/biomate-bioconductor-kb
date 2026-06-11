library(abseqR)
library(BiocParallel)

sandboxDirectory <- tempdir()
exdata <- system.file("extdata", "ex", package = "abseqR")
file.copy(exdata, sandboxDirectory, recursive = TRUE)
dataPath <- file.path(sandboxDirectory, "ex")

samples_obj <- abseqReport(
    dataPath,
    compare = c("PCR1, PCR2, PCR3"),
    report = 0,
    BPPARAM = SerialParam()
)

saveRDS(samples_obj, "samples")