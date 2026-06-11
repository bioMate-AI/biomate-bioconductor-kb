library(CytoPipeline)

rawDataDir <- system.file("extdata", package = "CytoPipeline")
fcs_files <- list.files(rawDataDir, pattern = "Donor", full.names = TRUE)

sampleFiles <- basename(fcs_files)
for (f in fcs_files) {
    file.copy(f, basename(f), overwrite = TRUE)
}