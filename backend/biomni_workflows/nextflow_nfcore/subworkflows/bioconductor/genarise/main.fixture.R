library(genArise)
data(Simon)
datos <- attr(Simon, "spotData")

cy3 <- datos$Cy3
cy5 <- datos$Cy5
bg_cy3 <- datos$BgCy3
bg_cy5 <- datos$BgCy5

if ("Id" %in% colnames(datos)) {
    ids <- datos$Id
} else if ("ID" %in% colnames(datos)) {
    ids <- datos$ID
} else {
    ids <- rownames(datos)
}

out_data <- data.frame(cy3, cy5, bg_cy3, bg_cy5, ids)

write.table(out_data, file = "raw_intensities.txt", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)