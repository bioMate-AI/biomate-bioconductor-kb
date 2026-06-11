library(PROcess)

# Generate fs
fdat <- system.file("Test", package="PROcess")
fs_orig <- list.files(fdat, pattern="\\.*csv\\.*", full.names=TRUE)
file.copy(fs_orig, ".")
fs <- basename(fs_orig)
saveRDS(fs, "fs.rds")

# Generate rtM
testdir <- system.file("Test", package = "PROcess")
testM <- rmBaseline(testdir)
rtM <- renorm(testM, cutoff=1500)

saveRDS(rtM, "rtM.rds")
write.csv(rtM, "rtM.csv", row.names = TRUE)