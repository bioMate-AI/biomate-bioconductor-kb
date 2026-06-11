library(alevinQC)

example_dir <- system.file("extdata/alevin_example_v0.14", package = "alevinQC")
dir.create("baseDir", showWarnings = FALSE, recursive = TRUE)
file.copy(list.files(example_dir, full.names = TRUE), "baseDir", recursive = TRUE)