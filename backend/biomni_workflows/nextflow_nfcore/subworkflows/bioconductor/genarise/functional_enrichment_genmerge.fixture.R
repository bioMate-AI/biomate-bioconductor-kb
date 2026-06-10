library(genArise)

expected_files <- c("association.txt", "description.txt", "population.genes", "study.genes")

for (f in expected_files) {
    shipped_file <- list.files(system.file(package = "genArise"), pattern = paste0("^", f, "$"), recursive = TRUE, full.names = TRUE)
    
    if (length(shipped_file) > 0 && file.exists(shipped_file[1])) {
        file.copy(shipped_file[1], f, overwrite = TRUE)
    } else {
        if (f == "population.genes") {
            pop_genes <- paste0("Gene", 1:100)
            write.table(pop_genes, f, row.names = FALSE, col.names = FALSE, quote = FALSE, sep = "\t")
        } else if (f == "study.genes") {
            study_genes <- paste0("Gene", 1:20)
            write.table(study_genes, f, row.names = FALSE, col.names = FALSE, quote = FALSE, sep = "\t")
        } else if (f == "association.txt") {
            pop_genes <- paste0("Gene", 1:100)
            assoc <- data.frame(
                Gene = rep(pop_genes, each = 2),
                GO = paste0("GO:", sprintf("%07d", sample(1:50, 200, replace = TRUE)))
            )
            write.table(assoc, f, row.names = FALSE, col.names = FALSE, quote = FALSE, sep = "\t")
        } else if (f == "description.txt") {
            desc <- data.frame(
                GO = paste0("GO:", sprintf("%07d", 1:50)),
                Description = paste("Synthetic GO term description", 1:50)
            )
            write.table(desc, f, row.names = FALSE, col.names = FALSE, quote = FALSE, sep = "\t")
        }
    }
}