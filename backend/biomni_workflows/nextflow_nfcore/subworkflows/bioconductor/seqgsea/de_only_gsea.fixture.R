library(SeqGSEA)

data.dir <- system.file("extdata", package="SeqGSEA", mustWork=TRUE)
orig_count_file <- file.path(data.dir, "geneCounts.txt")
orig_geneset_file <- file.path(data.dir, "gs_symb.txt")

# 1. Prepare and write count.file
if (file.exists(orig_count_file)) {
    # Read the original file and write it out matching the exact format expected by the workflow
    counts <- read.table(orig_count_file)
    write.table(counts, "count.file", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)
} else {
    # Fallback synthetic count.file
    geneCounts <- matrix(rnbinom(200, size=10, prob=0.5), nrow=20, ncol=10)
    rownames(geneCounts) <- paste0("ENSG000000000", 10:29)
    colnames(geneCounts) <- c(paste0("S", 1:5), paste0("C", 1:5))
    write.table(geneCounts, "count.file", sep="\t", quote=FALSE, row.names=TRUE, col.names=NA)
}

# 2. Prepare and write geneset.file
if (file.exists(orig_geneset_file)) {
    file.copy(orig_geneset_file, "geneset.file", overwrite = TRUE)
} else {
    # Fallback synthetic geneset.file (GMT format)
    # Requires at least 5 genes per set to pass genesetsize.min = 5
    gmt_lines <- c(
        paste("GeneSet1", "Description1", "ENSG00000000010", "ENSG00000000011", "ENSG00000000012", "ENSG00000000013", "ENSG00000000014", sep="\t"),
        paste("GeneSet2", "Description2", "ENSG00000000015", "ENSG00000000016", "ENSG00000000017", "ENSG00000000018", "ENSG00000000019", sep="\t")
    )
    writeLines(gmt_lines, "geneset.file")
}