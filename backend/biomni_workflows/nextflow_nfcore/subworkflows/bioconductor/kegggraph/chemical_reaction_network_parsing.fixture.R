library(KEGGgraph)

src_file <- system.file("extdata", "map00260.xml", package="KEGGgraph")

if (!file.exists(src_file)) {
    files <- list.files(system.file("extdata", package="KEGGgraph"), pattern="map00260\\.xml$", recursive=TRUE, full.names=TRUE)
    if (length(files) > 0) {
        src_file <- files[1]
    }
}

if (file.exists(src_file)) {
    file.copy(src_file, "map00260.xml", overwrite = TRUE)
} else {
    # Fallback: create a minimal valid KGML XML file if not found in package
    xml_content <- '<?xml version="1.0"?>
<!DOCTYPE pathway SYSTEM "http://www.kegg.jp/kegg/xml/KGML_v0.7.1_.dtd">
<pathway name="path:map00260" org="map" number="00260" title="Glycine, serine and threonine metabolism" image="http://www.kegg.jp/kegg/pathway/map/map00260.png" link="http://www.kegg.jp/kegg-bin/show_pathway?map00260">
</pathway>'
    writeLines(xml_content, "map00260.xml")
}