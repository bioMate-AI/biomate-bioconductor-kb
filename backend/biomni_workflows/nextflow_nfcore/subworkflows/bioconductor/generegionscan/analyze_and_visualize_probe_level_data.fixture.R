library(GeneRegionScan)
library(Biostrings)

data(exampleProbeLevelSet, package = "GeneRegionScan")

saveRDS(exampleProbeLevelSet, "exampleProbeLevelSet.rds")
saveRDS(mrna, "mrna.rds")
saveRDS(genomic, "genomic.rds")