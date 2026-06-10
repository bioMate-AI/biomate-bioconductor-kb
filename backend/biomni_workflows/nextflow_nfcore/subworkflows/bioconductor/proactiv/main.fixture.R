library(proActiv)
library(GenomicFeatures)

# 1. files: STAR or TopHat2 tab-delimited junction files
junction_files <- list.files(system.file('extdata/vignette/junctions', package = 'proActiv'), full.names = TRUE)
if (length(junction_files) > 0) {
    file.copy(junction_files[1], "files", overwrite = TRUE)
} else {
    # Create a dummy STAR junction file if not found
    df <- data.frame(
        chr = "chr1",
        intron_start = 10000,
        intron_end = 10100,
        strand = 1,
        intron_motif = 1,
        annotated = 1,
        unique_junction_reads = 50,
        multi_junction_reads = 10,
        max_overhang = 10
    )
    write.table(df, "files", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}

# 2. gtf.file: Genome annotation GTF file
gtf_file <- system.file('extdata/vignette/annotation/gencode.v34.annotation.subset.gtf.gz', package = 'proActiv')
if (gtf_file != "" && file.exists(gtf_file)) {
    file.copy(gtf_file, "gtf.file", overwrite = TRUE)
} else {
    # Create a dummy GTF
    gtf_content <- 'chr1\tHAVANA\tgene\t11869\t14409\t.\t+\t.\tgene_id "ENSG00000223972.5"; gene_type "transcribed_unprocessed_pseudogene"; gene_name "DDX11L1"; level 2; hgnc_id "HGNC:37102"; havana_gene "OTTHUMG00000000961.2";\n'
    writeLines(gtf_content, "gtf.file")
}

# 3. txdb.file: TxDb SQLite database file
txdb_file <- system.file('extdata/vignette/annotation/gencode.v34.annotation.subset.sqlite', package = 'proActiv')
if (txdb_file != "" && file.exists(txdb_file)) {
    file.copy(txdb_file, "txdb.file", overwrite = TRUE)
} else {
    txdb <- makeTxDbFromGFF("gtf.file", format = "gtf")
    saveDb(txdb, "txdb.file")
}