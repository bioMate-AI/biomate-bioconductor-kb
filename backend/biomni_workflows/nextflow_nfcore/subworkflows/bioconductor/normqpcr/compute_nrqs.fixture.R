library(NormqPCR)
library(ReadqPCR)

# 1. qPCR.example.txt
qpcr_candidates <- c(
    list.files(system.file("exData", package = "ReadqPCR"), pattern = "qPCR\\.example\\.txt$", full.names = TRUE, recursive = TRUE),
    list.files(system.file("extdata", package = "ReadqPCR"), pattern = "qPCR\\.example\\.txt$", full.names = TRUE, recursive = TRUE),
    list.files(system.file("exData", package = "NormqPCR"), pattern = "qPCR\\.example\\.txt$", full.names = TRUE, recursive = TRUE),
    list.files(system.file("extdata", package = "NormqPCR"), pattern = "qPCR\\.example\\.txt$", full.names = TRUE, recursive = TRUE)
)

if (length(qpcr_candidates) > 0 && file.exists(qpcr_candidates[1])) {
    file.copy(qpcr_candidates[1], "qPCR.example.txt", overwrite = TRUE)
} else {
    # Fallback synthetic file matching the expected format
    qpcr_data <- data.frame(
        Well = c("A1", "A2", "A3", "A4"),
        Sample = c("Sample1", "Sample1", "Sample2", "Sample2"),
        Detector = c("gene_az", "gene_gx", "gene_az", "gene_gx"),
        Cq = c(20.1, 22.3, 19.8, 21.5)
    )
    write.table(qpcr_data, file = "qPCR.example.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

# 2. Efficiencies.txt
eff_candidates <- c(
    list.files(system.file("exData", package = "ReadqPCR"), pattern = "Efficiencies\\.txt$", full.names = TRUE, recursive = TRUE),
    list.files(system.file("extdata", package = "ReadqPCR"), pattern = "Efficiencies\\.txt$", full.names = TRUE, recursive = TRUE),
    list.files(system.file("exData", package = "NormqPCR"), pattern = "Efficiencies\\.txt$", full.names = TRUE, recursive = TRUE),
    list.files(system.file("extdata", package = "NormqPCR"), pattern = "Efficiencies\\.txt$", full.names = TRUE, recursive = TRUE)
)

if (length(eff_candidates) > 0 && file.exists(eff_candidates[1])) {
    file.copy(eff_candidates[1], "Efficiencies.txt", overwrite = TRUE)
} else {
    # Fallback synthetic file matching the expected format
    eff_data <- data.frame(
        Gene = c("gene_az", "gene_gx"),
        efficiency = c(1.95, 1.98),
        SD.efficiency = c(0.02, 0.01)
    )
    write.table(eff_data, file = "Efficiencies.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}