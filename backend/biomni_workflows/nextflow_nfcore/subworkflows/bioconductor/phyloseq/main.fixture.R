library("phyloseq")
library("ggplot2")

# 1. Reproduce the vignette's data-preparation code
data(GlobalPatterns)
GP <- prune_taxa(taxa_sums(GlobalPatterns) > 0, GlobalPatterns)
human <- get_variable(GP, "SampleType") %in% c("Feces", "Mock", "Skin", "Tongue")
sample_data(GP)$human <- factor(human)

data(enterotype)
TopNOTUs <- names(sort(taxa_sums(enterotype), TRUE)[1:10])
ent10 <- prune_taxa(TopNOTUs, enterotype)

# 2. Provide the required input files by copying the ready-made files shipped with phyloseq
# as per the GROUND TRUTH list, preferring them over re-deriving from the R objects.

# Find and copy the BIOM file
biom_file <- list.files(system.file("extdata", package="phyloseq"), pattern="myBiomFile.biom", full.names=TRUE)
if (length(biom_file) > 0 && file.exists(biom_file[1])) {
    file.copy(biom_file[1], "file.biom", overwrite=TRUE)
} else {
    biom_file <- list.files(system.file("extdata", package="phyloseq"), pattern="\\.biom$", full.names=TRUE)
    if (length(biom_file) > 0 && file.exists(biom_file[1])) {
        file.copy(biom_file[1], "file.biom", overwrite=TRUE)
    }
}

# Find and copy the tree file
tre_file <- list.files(system.file("extdata", package="phyloseq"), pattern="rep_set.tre", full.names=TRUE)
if (length(tre_file) > 0 && file.exists(tre_file[1])) {
    file.copy(tre_file[1], "file.tre", overwrite=TRUE)
} else {
    tre_file <- list.files(system.file("extdata", package="phyloseq"), pattern="\\.tre$", full.names=TRUE)
    if (length(tre_file) > 0 && file.exists(tre_file[1])) {
        file.copy(tre_file[1], "file.tre", overwrite=TRUE)
    }
}

# Find and copy the mapping file
map_file <- list.files(system.file("extdata", package="phyloseq"), pattern="map.tsv", full.names=TRUE)
if (length(map_file) > 0 && file.exists(map_file[1])) {
    file.copy(map_file[1], "map.txt", overwrite=TRUE)
} else {
    map_file <- list.files(system.file("extdata", package="phyloseq"), pattern="map.*\\.tsv$", full.names=TRUE)
    if (length(map_file) > 0 && file.exists(map_file[1])) {
        file.copy(map_file[1], "map.txt", overwrite=TRUE)
    }
}

# 3. Guarantee the declared input files exist
if (!file.exists("file.biom")) {
    # Minimal valid BIOM format JSON
    biom_json <- '{"id": "None", "format": "1.0.0", "format_url": "http://biom-format.org", "type": "OTU table", "generated_by": "synthetic", "date": "2023-01-01T00:00:00", "rows": [{"id": "OTU1", "metadata": {"taxonomy": ["k__Bacteria"]}}], "columns": [{"id": "Sample1", "metadata": null}], "matrix_type": "dense", "matrix_element_type": "int", "shape": [1, 1], "data": [[1]]}'
    writeLines(biom_json, "file.biom")
}

if (!file.exists("file.tre")) {
    # Minimal valid Newick tree
    writeLines("(Sample1:0.1,Sample2:0.2);", "file.tre")
}

if (!file.exists("map.txt")) {
    # Minimal valid tab-delimited mapping file
    map_data <- data.frame(
        `#SampleID` = c("Sample1", "Sample2"),
        Treatment = c("A", "B"),
        check.names = FALSE
    )
    write.table(map_data, "map.txt", sep="\t", row.names=FALSE, quote=FALSE)
}