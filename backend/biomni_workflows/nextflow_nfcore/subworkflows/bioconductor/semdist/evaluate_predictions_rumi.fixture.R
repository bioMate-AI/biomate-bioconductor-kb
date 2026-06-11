library(SemDist)

truefile <- system.file("extdata", "MFO_LABELS_TEST.txt", package="SemDist")
if (file.exists(truefile)) {
    file.copy(truefile, "MFO_LABELS_TEST.txt", overwrite = TRUE)
} else {
    labels <- data.frame(V1 = c("prot1", "prot2"), V2 = c("GO:0003674", "GO:0005575"))
    write.table(labels, "MFO_LABELS_TEST.txt", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}

predfile <- system.file("extdata", "MFO_PREDS_TEST.txt", package="SemDist")
if (file.exists(predfile)) {
    file.copy(predfile, "MFO_PREDS_TEST.txt", overwrite = TRUE)
} else {
    preds <- data.frame(V1 = c("prot1", "prot2"), V2 = c("GO:0003674", "GO:0005575"), V3 = c("0.9", "0.8"))
    write.table(preds, "MFO_PREDS_TEST.txt", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}