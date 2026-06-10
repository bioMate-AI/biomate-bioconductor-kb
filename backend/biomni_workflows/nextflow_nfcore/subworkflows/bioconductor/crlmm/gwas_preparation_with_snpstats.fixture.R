require(oligoClasses)
library(crlmm)
library(hapmapsnp6)

path <- system.file("celFiles", package="hapmapsnp6")
celFiles <- list.celfiles(path, full.names=TRUE)
crlmmResult <- crlmm(celFiles, verbose=FALSE)

saveRDS(crlmmResult, "crlmmResult")
saveRDS(crlmmResult, "crlmmResult.rds")