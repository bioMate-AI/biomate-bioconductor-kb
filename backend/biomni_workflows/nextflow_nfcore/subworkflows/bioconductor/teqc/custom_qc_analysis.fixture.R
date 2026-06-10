library(TEQC)

exptPath <- system.file("extdata", package = "TEQC")

targets_src <- file.path(exptPath, "ExampleSet_Targets.bed")
reads_src <- file.path(exptPath, "ExampleSet_Reads.bed")
baits_src <- file.path(exptPath, "ExampleSet_Baits.txt")

if (file.exists(targets_src)) {
    file.copy(targets_src, "ExampleSet_Targets.bed", overwrite = TRUE)
} else {
    stop("Source file ExampleSet_Targets.bed not found in TEQC extdata")
}

if (file.exists(reads_src)) {
    file.copy(reads_src, "ExampleSet_Reads.bed", overwrite = TRUE)
} else {
    stop("Source file ExampleSet_Reads.bed not found in TEQC extdata")
}

if (file.exists(baits_src)) {
    file.copy(baits_src, "ExampleSet_Baits.txt", overwrite = TRUE)
} else {
    stop("Source file ExampleSet_Baits.txt not found in TEQC extdata")
}