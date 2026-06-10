library(NoRCE)

# Find the shipped GTF file from the package
fileImport <- system.file("extdata", "temp.gtf", package = "NoRCE")

if (fileImport != "" && file.exists(fileImport)) {
    file.copy(fileImport, "annotation.gtf", overwrite = TRUE)
} else {
    # Fallback: create a minimal GTF file with biotypes mentioned in the vignette
    gtf_content <- c(
        'chr1\tHAVANA\tgene\t11869\t14409\t.\t+\t.\tgene_id "ENSG00000223972.5"; gene_type "transcribed_unprocessed_pseudogene"; gene_name "DDX11L1"; level 2; hgnc_id "HGNC:37102"; havana_gene "OTTHUMG00000000961.2";',
        'chr1\tHAVANA\ttranscript\t11869\t14409\t.\t+\t.\tgene_id "ENSG00000223972.5"; transcript_id "ENST00000456328.2"; gene_type "transcribed_unprocessed_pseudogene"; gene_name "DDX11L1"; transcript_type "processed_transcript"; transcript_name "DDX11L1-202"; level 2; transcript_support_level "1"; hgnc_id "HGNC:37102"; tag "basic"; havana_gene "OTTHUMG00000000961.2"; havana_transcript "OTTHUMT00000362751.1";',
        'chr1\tHAVANA\tgene\t14404\t29570\t.\t-\t.\tgene_id "ENSG00000227232.5"; gene_type "unprocessed_pseudogene"; gene_name "WASH7P"; level 2; hgnc_id "HGNC:38034"; havana_gene "OTTHUMG00000000958.1";'
    )
    writeLines(gtf_content, "annotation.gtf")
}