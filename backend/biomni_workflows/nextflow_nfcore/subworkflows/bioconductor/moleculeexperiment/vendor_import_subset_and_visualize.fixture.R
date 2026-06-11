library(MoleculeExperiment)

raw_data_dir <- "raw_data_dir"
dir.create(raw_data_dir, showWarnings = FALSE, recursive = TRUE)

repoDir <- system.file("extdata", "xenium_V1_FF_Mouse_Brain", package = "MoleculeExperiment")
if (nzchar(repoDir) && dir.exists(repoDir)) {
    files_to_copy <- list.files(repoDir, full.names = TRUE)
    file.copy(files_to_copy, raw_data_dir, recursive = TRUE)
}