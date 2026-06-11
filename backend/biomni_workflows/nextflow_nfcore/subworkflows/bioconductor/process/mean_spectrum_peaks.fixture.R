library(PROcess)

fdat <- system.file("Test", package="PROcess")
fs <- list.files(fdat, pattern="\\.*csv\\.*", full.names=TRUE)

testdir <- system.file("Test", package = "PROcess")
testM <- rmBaseline(testdir)
rtM <- renorm(testM, cutoff=1500)

saveRDS(fs, "fs")
saveRDS(rtM, "rtM")