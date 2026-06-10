library(MSnID)

human_brain_src <- system.file("extdata", "human_brain.txt", package="MSnID")
if (file.exists(human_brain_src)) {
    file.copy(human_brain_src, "human_brain.txt", overwrite = TRUE)
}

c_elegans_src <- system.file("extdata", "c_elegans.mzid.gz", package="MSnID")
if (file.exists(c_elegans_src)) {
    file.copy(c_elegans_src, "c_elegans.mzid.gz", overwrite = TRUE)
}