library(musicatk)

luad_count_table_path <- system.file("extdata", "luad_tcga_count_table.csv", package = "musicatk")

if (luad_count_table_path != "" && file.exists(luad_count_table_path)) {
    file.copy(luad_count_table_path, "luad_tcga_count_table.csv", overwrite = TRUE)
} else {
    # Construct a synthetic SBS96 count table if the file is not shipped
    bases <- c("A", "C", "G", "T")
    muts <- c("C>A", "C>G", "C>T", "T>A", "T>C", "T>G")
    motifs <- c()
    
    for (m in muts) {
        orig <- substr(m, 1, 1)
        for (up in bases) {
            for (down in bases) {
                motifs <- c(motifs, paste0(m, "_", up, orig, down))
            }
        }
    }
    
    set.seed(123)
    counts <- matrix(rpois(96 * 3, lambda = 10), nrow = 96, ncol = 3)
    rownames(counts) <- motifs
    colnames(counts) <- c("TCGA-56-7582-01A-11D-2042-08", 
                          "TCGA-77-7335-01A-11D-2042-08", 
                          "TCGA-94-7557-01A-11D-2122-08")
    
    write.csv(counts, "luad_tcga_count_table.csv", row.names = TRUE)
}