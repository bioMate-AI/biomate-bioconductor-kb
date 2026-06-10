library(crlmm)
library(hapmapsnp6)
library(oligoClasses)

path <- system.file("celFiles", package="hapmapsnp6")
celFiles_source <- list.celfiles(path, full.names=TRUE)

for (f in celFiles_source) {
    file.copy(f, basename(f), overwrite = TRUE)
}