library(EnrichmentBrowser)

# The files are shipped in the package's extdata directory
extdata_dir <- system.file("extdata", package = "EnrichmentBrowser")
files_to_find <- c("exprs.tab", "colData.tab", "rowData.tab", "hsa_kegg_gs.gmt", "hsa.grn")

for (f in files_to_find) {
    found <- list.files(extdata_dir, pattern = paste0("^", f, "$"), recursive = TRUE, full.names = TRUE)
    
    if (length(found) > 0) {
        file.copy(found[1], f, overwrite = TRUE)
    } else {
        # Fallback generation if the file is not found in the installed package
        if (f == "exprs.tab") {
            mat <- matrix(rnorm(100), nrow = 10, ncol = 10)
            rownames(mat) <- paste0("gene", 1:10)
            colnames(mat) <- paste0("sample", 1:10)
            write.table(mat, f, sep = "\t", quote = FALSE, col.names = NA)
        } else if (f == "colData.tab") {
            cd <- data.frame(GROUP = rep(c(0, 1), each = 5), row.names = paste0("sample", 1:10))
            write.table(cd, f, sep = "\t", quote = FALSE, col.names = NA)
        } else if (f == "rowData.tab") {
            rd <- data.frame(ENTREZID = paste0("gene", 1:10), row.names = paste0("gene", 1:10))
            write.table(rd, f, sep = "\t", quote = FALSE, col.names = NA)
        } else if (f == "hsa_kegg_gs.gmt") {
            cat("pathway1\thttp://example.com\tgene1\tgene2\n", file = f)
        } else if (f == "hsa.grn") {
            grn <- data.frame(from = c("gene1", "gene2"), to = c("gene2", "gene3"), weight = c(1, 1))
            write.table(grn, f, sep = "\t", quote = FALSE, row.names = FALSE)
        }
    }
}