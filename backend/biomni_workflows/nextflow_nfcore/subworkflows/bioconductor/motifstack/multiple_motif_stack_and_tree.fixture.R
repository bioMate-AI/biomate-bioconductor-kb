library(motifStack)

dir.create("motifs_folder", showWarnings = FALSE, recursive = TRUE)

pcm_files <- list.files(system.file("extdata", package = "motifStack"), pattern = "pcm$", full.names = TRUE)

if (length(pcm_files) > 0) {
    file.copy(pcm_files, "motifs_folder")
} else {
    # Fallback synthetic .pcm file if none are found in the installation
    dummy_pcm <- data.frame(
        V1 = c("A", "C", "G", "T"),
        V2 = c("A", "C", "G", "T"),
        V3 = c(10, 2, 3, 4),
        V4 = c(4, 10, 2, 1),
        V5 = c(2, 2, 10, 2)
    )
    write.table(dummy_pcm, file.path("motifs_folder", "dummy.pcm"), sep = "\t", quote = FALSE, col.names = FALSE, row.names = FALSE)
}