library(IPO)
library(faahKO)

datapath <- system.file("cdf", package = "faahKO")
datafiles_source <- list.files(datapath, recursive = TRUE, full.names = TRUE)

for (f in datafiles_source) {
    file.copy(f, basename(f), overwrite = TRUE)
}