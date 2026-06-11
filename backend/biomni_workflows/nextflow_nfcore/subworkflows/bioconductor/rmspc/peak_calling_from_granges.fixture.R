library(rmspc)
library(rtracklayer)

path <- system.file("extdata", package = "rmspc")
input1 <- file.path(path, "rep1.bed")
input2 <- file.path(path, "rep2.bed")

gr1 <- rtracklayer::import(input1, format = "bed")
gr2 <- rtracklayer::import(input2, format = "bed")

saveRDS(gr1, "GR1")
saveRDS(gr2, "GR2")