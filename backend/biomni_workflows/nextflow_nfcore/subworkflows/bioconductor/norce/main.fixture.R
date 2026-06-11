library(NoRCE)

# 1. Create brain_disorder_ncRNA (ncRNA gene list)
# Try to use the shipped gene_list.txt, otherwise create a synthetic one
gene_list_file <- system.file("extdata", "gene_list.txt", package = "NoRCE")
if (file.exists(gene_list_file) && nzchar(gene_list_file)) {
    file.copy(gene_list_file, "brain_disorder_ncRNA", overwrite = TRUE)
} else {
    # Synthetic Ensembl gene IDs
    writeLines(c("ENSG00000228630", "ENSG00000283486", "ENSG00000284733"), "brain_disorder_ncRNA")
}

# 2. Create DER-18_TAD_adultbrain.txt (custom TAD boundaries BED file)
# Try to use the shipped custom_tad.bed, otherwise create a synthetic BED file
custom_tad_file <- system.file("extdata", "custom_tad.bed", package = "NoRCE")
if (file.exists(custom_tad_file) && nzchar(custom_tad_file)) {
    file.copy(custom_tad_file, "DER-18_TAD_adultbrain.txt", overwrite = TRUE)
} else {
    bed_data <- data.frame(
        chrom = c("chr1", "chr1"),
        chromStart = c(10000, 30000),
        chromEnd = c(20000, 40000),
        name = c("TAD1", "TAD2")
    )
    write.table(bed_data, "DER-18_TAD_adultbrain.txt", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
}

# 3. Create miRCancer.db (local correlation database)
# Create a synthetic SQLite database with dummy tables for correlation
if (requireNamespace("RSQLite", quietly = TRUE)) {
    con <- RSQLite::dbConnect(RSQLite::SQLite(), "miRCancer.db")
    
    # Create dummy tables that might be expected by the correlation analysis
    mirna_mrna_df <- data.frame(
        mirna = c("hsa-mir-1", "hsa-mir-2"), 
        mrna = c("ENSG00000228630", "ENSG00000283486"), 
        correlation = c(0.95, -0.85), 
        cancer = c("GBMLGG", "GBMLGG")
    )
    mirna_lncrna_df <- data.frame(
        mirna = c("hsa-mir-1", "hsa-mir-2"), 
        lncrna = c("ENSG00000284733", "ENSG00000228630"), 
        correlation = c(0.88, -0.92), 
        cancer = c("GBMLGG", "GBMLGG")
    )
    
    RSQLite::dbWriteTable(con, "mirna_mrna", mirna_mrna_df, overwrite = TRUE)
    RSQLite::dbWriteTable(con, "mirna_lncrna", mirna_lncrna_df, overwrite = TRUE)
    RSQLite::dbDisconnect(con)
} else {
    # Fallback to creating an empty file if RSQLite is not available
    file.create("miRCancer.db")
}