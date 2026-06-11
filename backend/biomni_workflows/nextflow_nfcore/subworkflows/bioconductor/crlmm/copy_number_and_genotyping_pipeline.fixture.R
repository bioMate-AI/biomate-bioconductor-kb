library(crlmm)
library(hapmapsnp6)
library(oligoClasses)

path <- system.file("celFiles", package="hapmapsnp6")
cel_files_source <- list.celfiles(path, full.names=TRUE)

for (f in cel_files_source) {
    file.copy(f, basename(f), overwrite = TRUE)
}