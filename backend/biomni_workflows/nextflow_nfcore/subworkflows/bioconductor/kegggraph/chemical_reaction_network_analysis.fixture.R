library(KEGGgraph)

mapfile <- system.file("extdata", "map00260.xml", package="KEGGgraph")
if (file.exists(mapfile)) {
    file.copy(mapfile, "map00260.xml", overwrite = TRUE)
} else {
    stop("map00260.xml not found in KEGGgraph extdata")
}