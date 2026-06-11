suppressPackageStartupMessages({
    library(cfDNAPro)
})

example_data_path <- cfDNAPro::examplePath("groups_picard")

dir.create("data_path", showWarnings = FALSE, recursive = TRUE)

files_to_copy <- list.files(example_data_path, full.names = TRUE)
for (f in files_to_copy) {
    file.copy(f, "data_path", recursive = TRUE)
}