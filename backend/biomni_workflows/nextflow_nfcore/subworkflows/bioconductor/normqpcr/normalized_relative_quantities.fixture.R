library(NormqPCR)
library(ReadqPCR)

path <- system.file("exData", package = "ReadqPCR")
qPCR.example <- file.path(path, "qPCR.example.txt")
Effs <- file.path(path, "Efficiencies.txt")

if (file.exists(qPCR.example)) {
    file.copy(qPCR.example, "qPCR.example.txt", overwrite = TRUE)
} else {
    df_qpcr <- data.frame(
        Well = c("A1", "A2", "A3", "A4"),
        Sample = c("S1", "S1", "S2", "S2"),
        Detector = c("gene_az", "gene_gx", "gene_az", "gene_gx"),
        Task = rep("Unknown", 4),
        Cq = c(20.1, 21.2, 19.5, 22.1)
    )
    write.table(df_qpcr, "qPCR.example.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

if (file.exists(Effs)) {
    file.copy(Effs, "Efficiencies.txt", overwrite = TRUE)
} else {
    df_effs <- data.frame(
        efficiency = c(1.9, 2.0),
        SD.efficiency = c(0.05, 0.02)
    )
    rownames(df_effs) <- c("gene_az", "gene_gx")
    write.table(df_effs, "Efficiencies.txt", sep = "\t", row.names = TRUE, quote = FALSE)
}