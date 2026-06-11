library(FISHalyseR)
library(EBImage)

f <- system.file("extdata", "SampleFISHgray.jpg", package="FISHalyseR")

if (file.exists(f)) {
    file.copy(f, "SampleFISHgray.jpg", overwrite = TRUE)
} else {
    # Fallback to generate a synthetic image if the package file is missing
    img <- Image(matrix(runif(10000), 100, 100))
    writeImage(img, "SampleFISHgray.jpg")
}