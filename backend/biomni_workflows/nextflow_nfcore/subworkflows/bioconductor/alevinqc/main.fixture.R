library(alevinQC)

example_dir <- system.file("extdata/alevin_example_v0.14", package = "alevinQC")
baseDir <- "baseDir"
dir.create(baseDir, showWarnings = FALSE)
file.copy(from = list.files(example_dir, full.names = TRUE), to = baseDir, recursive = TRUE)