library(SemDist)

ontfile <- system.file("extdata", "mfo_ontology.txt", package="SemDist")
if (file.exists(ontfile)) {
    file.copy(ontfile, "mfo_ontology.txt", overwrite = TRUE)
} else {
    # Fallback synthetic data if missing
    cat("GO:0003674\tGO:0000001\nGO:0003674\tGO:0000002\n", file="mfo_ontology.txt")
}

annotations <- system.file("extdata", "MFO_LABELS_TEST.txt", package="SemDist")
if (file.exists(annotations)) {
    file.copy(annotations, "MFO_LABELS_TEST.txt", overwrite = TRUE)
} else {
    # Fallback synthetic data if missing
    cat("prot1\tGO:0000001\nprot2\tGO:0000002\n", file="MFO_LABELS_TEST.txt")
}