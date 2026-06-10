library(cfDNAPro)

data_path <- examplePath("groups_picard")

if (!file.exists(basename(data_path))) {
    file.copy(data_path, ".", recursive = TRUE)
}