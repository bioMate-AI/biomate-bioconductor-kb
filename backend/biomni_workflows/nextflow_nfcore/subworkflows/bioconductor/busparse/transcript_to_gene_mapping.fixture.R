library(BUSpaRse)

fasta_files <- list.files(system.file(package = "BUSpaRse"), pattern = "fasta_test\\.fasta$", recursive = TRUE, full.names = TRUE)
if (length(fasta_files) > 0) {
    file.copy(fasta_files[1], "fasta_test.fasta", overwrite = TRUE)
} else {
    writeLines(c(">ENST00000434970.2 cdna chromosome:GRCh38:14:22438547:22438554:1 gene:ENSG00000237235.2 gene_biotype:TR_D_gene transcript_biotype:TR_D_gene gene_symbol:TRDD2 description:T cell receptor delta diversity 2",
                 "ACTG"), "fasta_test.fasta")
}

gtf_files <- list.files(system.file(package = "BUSpaRse"), pattern = "gtf_test\\.gtf$", recursive = TRUE, full.names = TRUE)
if (length(gtf_files) > 0) {
    file.copy(gtf_files[1], "gtf_test.gtf", overwrite = TRUE)
} else {
    writeLines(c('14\tHAVANA\tgene\t22438547\t22438554\t.\t+\t.\tgene_id "ENSG00000237235.2"; gene_type "TR_D_gene"; gene_name "TRDD2"; level 2; tag "ncRNA_host";',
                 '14\tHAVANA\ttranscript\t22438547\t22438554\t.\t+\t.\tgene_id "ENSG00000237235.2"; transcript_id "ENST00000434970.2"; gene_type "TR_D_gene"; gene_name "TRDD2"; transcript_type "TR_D_gene"; transcript_name "TRDD2-201"; level 2; transcript_support_level "NA"; tag "basic"; tag "Ensembl_canonical";',
                 '14\tHAVANA\texon\t22438547\t22438554\t.\t+\t.\tgene_id "ENSG00000237235.2"; transcript_id "ENST00000434970.2"; gene_type "TR_D_gene"; gene_name "TRDD2"; transcript_type "TR_D_gene"; transcript_name "TRDD2-201"; exon_number 1; exon_id "ENSE00001700869.1"; level 2; transcript_support_level "NA"; tag "basic"; tag "Ensembl_canonical";'), "gtf_test.gtf")
}