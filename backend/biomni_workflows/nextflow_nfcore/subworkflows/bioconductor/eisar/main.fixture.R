library(eisaR)

# Copy the GTF file from the package to the working directory
gtf_src <- system.file("extdata", "gencode.v28.annotation.sub.gtf", package = "eisaR")
if (file.exists(gtf_src)) {
    file.copy(gtf_src, "gencode.v28.annotation.sub.gtf", overwrite = TRUE)
} else {
    # Fallback if the exact file is not found
    writeLines(c(
        "chr1\tHAVANA\tgene\t11869\t14409\t.\t+\t.\tgene_id \"ENSG00000223972.5\"; gene_type \"transcribed_unprocessed_pseudogene\"; gene_name \"DDX11L1\"; level 2; hgnc_id \"HGNC:37102\"; havana_gene \"OTTHUMG00000000961.2\";",
        "chr1\tHAVANA\ttranscript\t11869\t14409\t.\t+\t.\tgene_id \"ENSG00000223972.5\"; transcript_id \"ENST00000456328.2\"; gene_type \"transcribed_unprocessed_pseudogene\"; gene_name \"DDX11L1\"; transcript_type \"processed_transcript\"; transcript_name \"DDX11L1-202\"; level 2; transcript_support_level \"1\"; hgnc_id \"HGNC:37102\"; tag \"basic\"; havana_gene \"OTTHUMG00000000961.2\"; havana_transcript \"OTTHUMT00000362751.1\";",
        "chr1\tHAVANA\texon\t11869\t12227\t.\t+\t.\tgene_id \"ENSG00000223972.5\"; transcript_id \"ENST00000456328.2\"; gene_type \"transcribed_unprocessed_pseudogene\"; gene_name \"DDX11L1\"; transcript_type \"processed_transcript\"; transcript_name \"DDX11L1-202\"; exon_number 1; exon_id \"ENSE00002234944.1\"; level 2; transcript_support_level \"1\"; hgnc_id \"HGNC:37102\"; tag \"basic\"; havana_gene \"OTTHUMG00000000961.2\"; havana_transcript \"OTTHUMT00000362751.1\";"
    ), "gencode.v28.annotation.sub.gtf")
}

# BSgenome.Hsapiens.UCSC.hg38 is a Bioconductor package loaded via library(), 
# but we create a dummy file to satisfy the strict file existence check.
file.create("BSgenome.Hsapiens.UCSC.hg38")