library(cfDNAPro)

data_path <- examplePath("groups_picard")
if (file.exists(data_path)) {
    file.copy(data_path, ".", recursive = TRUE)
} else {
    # Fallback if examplePath fails or directory is missing
    dir.create("groups_picard", showWarnings = FALSE)
}