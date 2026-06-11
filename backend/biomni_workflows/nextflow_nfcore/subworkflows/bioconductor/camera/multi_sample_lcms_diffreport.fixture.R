library(CAMERA)
library(xcms)

file <- system.file('mzML/MM14.mzML', package = "CAMERA")
xs <- xcmsSet(file, method="centWave", ppm=30, peakwidth=c(5,10))

saveRDS(xs, "faahko.rds")