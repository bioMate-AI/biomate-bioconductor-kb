library(Rqc)
library(ShortRead)

folder <- system.file(package="ShortRead", "extdata/E-MTAB-1147")
src_files <- list.files(folder, pattern="fastq.gz", full.names=TRUE)

file.copy(src_files, ".", overwrite = TRUE)

files <- normalizePath(list.files(".", pattern="fastq.gz"))