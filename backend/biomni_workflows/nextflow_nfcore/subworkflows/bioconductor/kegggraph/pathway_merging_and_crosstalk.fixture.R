library(KEGGgraph)

mapk_src <- system.file("extdata", "hsa04010.xml", package="KEGGgraph")
if (!file.exists(mapk_src) || mapk_src == "") {
    xml_files <- list.files(system.file("extdata", package="KEGGgraph"), pattern="hsa04010\\.xml$", recursive=TRUE, full.names=TRUE)
    if (length(xml_files) > 0) mapk_src <- xml_files[1]
}

wnt_src <- system.file("extdata", "hsa04310.xml", package="KEGGgraph")
if (!file.exists(wnt_src) || wnt_src == "") {
    xml_files <- list.files(system.file("extdata", package="KEGGgraph"), pattern="hsa04310\\.xml$", recursive=TRUE, full.names=TRUE)
    if (length(xml_files) > 0) wnt_src <- xml_files[1]
}

if (file.exists(mapk_src) && mapk_src != "") {
    file.copy(mapk_src, "hsa04010.xml", overwrite = TRUE)
} else {
    writeLines('<?xml version="1.0"?>\n<pathway name="path:hsa04010" org="hsa" number="04010" title="MAPK signaling pathway"></pathway>', "hsa04010.xml")
}

if (file.exists(wnt_src) && wnt_src != "") {
    file.copy(wnt_src, "hsa04310.xml", overwrite = TRUE)
} else {
    writeLines('<?xml version="1.0"?>\n<pathway name="path:hsa04310" org="hsa" number="04310" title="Wnt signaling pathway"></pathway>', "hsa04310.xml")
}