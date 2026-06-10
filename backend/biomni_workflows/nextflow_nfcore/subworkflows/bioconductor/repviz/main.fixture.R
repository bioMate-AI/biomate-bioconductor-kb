suppressPackageStartupMessages({
  library(RepViz)
  library(GenomicRanges)
})

extdata_files <- list.files(system.file("extdata", package = "RepViz"), full.names = TRUE)
file.copy(from = extdata_files, to = ".", overwrite = TRUE)