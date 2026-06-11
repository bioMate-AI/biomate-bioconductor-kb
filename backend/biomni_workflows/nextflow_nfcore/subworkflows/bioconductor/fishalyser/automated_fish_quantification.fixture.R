library(FISHalyseR)

files_to_copy <- c("SampleFISH.jpg", "SampleFISH_R.jpg", "SampleFISH_G.jpg")

for (f in files_to_copy) {
    src <- system.file("extdata", f, package = "FISHalyseR")
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        stop(paste("Required file not found in package extdata:", f))
    }
}