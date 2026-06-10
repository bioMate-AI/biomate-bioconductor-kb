library(simpleSeg)
library(EBImage)
library(cytomapper)

pathToImages <- system.file("extdata", package = "simpleSeg")
imageDirs <- dir(pathToImages, "Point", full.names = TRUE)

for (d in imageDirs) {
  file.copy(d, ".", recursive = TRUE)
}