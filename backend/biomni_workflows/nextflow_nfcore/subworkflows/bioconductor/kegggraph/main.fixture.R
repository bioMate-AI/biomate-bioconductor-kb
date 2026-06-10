library(KEGGgraph)

src_file <- system.file("extdata", "hsa04010.xml", package="KEGGgraph")
if (file.exists(src_file)) {
    file.copy(src_file, "hsa04010.xml", overwrite = TRUE)
} else {
    stop("Source file hsa04010.xml not found in KEGGgraph package.")
}