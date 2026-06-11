library(puma)
suppressWarnings(suppressPackageStartupMessages(require(pumadata)))

data(eset_estrogen_mmgmos)
data(Clustii.exampleE)
data(Clustii.exampleStd)

saveRDS(eset_estrogen_mmgmos, "eset_estrogen_mmgmos")
saveRDS(Clustii.exampleE, "Clustii.exampleE")
saveRDS(Clustii.exampleStd, "Clustii.exampleStd")