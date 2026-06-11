library(flagme)
library(gcspikelite)

gcmsPath <- paste(find.package("gcspikelite"), "data", sep="/")
data(targets, package="gcspikelite")
cdfFiles <- paste(gcmsPath, targets$FileName, sep="/")
eluFiles <- gsub("CDF", "ELU", cdfFiles)

for (f in c(cdfFiles, eluFiles)) {
    if (file.exists(f)) {
        file.copy(f, basename(f), overwrite = TRUE)
    }
}