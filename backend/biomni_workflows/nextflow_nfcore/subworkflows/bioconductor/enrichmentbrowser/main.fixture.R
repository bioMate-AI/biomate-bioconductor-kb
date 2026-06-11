library(EnrichmentBrowser)

data.dir <- system.file("extdata", package = "EnrichmentBrowser")

# Copy exprs.tab
exprs_src <- file.path(data.dir, "exprs.tab")
if (file.exists(exprs_src)) {
    file.copy(exprs_src, "exprs.tab", overwrite = TRUE)
} else {
    # Fallback if not found
    exprs_data <- matrix(rnorm(100), nrow=10, ncol=10)
    rownames(exprs_data) <- paste0("Gene", 1:10)
    colnames(exprs_data) <- paste0("Sample", 1:10)
    write.table(exprs_data, "exprs.tab", sep="\t", quote=FALSE)
}

# Copy colData.tab
cdat_src <- file.path(data.dir, "colData.tab")
if (file.exists(cdat_src)) {
    file.copy(cdat_src, "colData.tab", overwrite = TRUE)
} else {
    # Fallback if not found
    cdat_data <- data.frame(GROUP = rep(c(0, 1), each=5))
    rownames(cdat_data) <- paste0("Sample", 1:10)
    write.table(cdat_data, "colData.tab", sep="\t", quote=FALSE)
}

# Copy rowData.tab
rdat_src <- file.path(data.dir, "rowData.tab")
if (file.exists(rdat_src)) {
    file.copy(rdat_src, "rowData.tab", overwrite = TRUE)
} else {
    # Fallback if not found
    rdat_data <- data.frame(ENTREZID = paste0("Gene", 1:10))
    rownames(rdat_data) <- paste0("Gene", 1:10)
    write.table(rdat_data, "rowData.tab", sep="\t", quote=FALSE)
}

# Copy hsa_kegg_gs.gmt
gmt_src <- file.path(data.dir, "hsa_kegg_gs.gmt")
if (file.exists(gmt_src)) {
    file.copy(gmt_src, "hsa_kegg_gs.gmt", overwrite = TRUE)
} else {
    # Fallback if not found
    writeLines(c(
        "hsa04110_Cell_cycle\t\tGene1\tGene2\tGene3",
        "hsa04115_p53_signaling_pathway\t\tGene4\tGene5\tGene6"
    ), "hsa_kegg_gs.gmt")
}