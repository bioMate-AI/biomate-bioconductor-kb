library(GeneRegionScan)
library(Biostrings)

data(exampleProbeLevelSet, package="GeneRegionScan")

saveRDS(exampleProbeLevelSet, "exampleProbeLevelSet")
saveRDS(mrna, "mrna")
saveRDS(genomic, "genomic")