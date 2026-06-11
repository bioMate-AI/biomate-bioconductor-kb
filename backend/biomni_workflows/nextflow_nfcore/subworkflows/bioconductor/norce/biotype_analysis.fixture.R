library(NoRCE)

gtf_content <- c(
  'chr1\tHAVANA\tgene\t11869\t14409\t.\t+\t.\tgene_id "ENSG00000223972.5"; gene_biotype "transcribed_unprocessed_pseudogene"; gene_name "DDX11L1";',
  'chr1\tHAVANA\ttranscript\t11869\t14409\t.\t+\t.\tgene_id "ENSG00000223972.5"; transcript_id "ENST00000456328.2"; gene_biotype "transcribed_unprocessed_pseudogene"; gene_name "DDX11L1";',
  'chr1\tHAVANA\texon\t11869\t12227\t.\t+\t.\tgene_id "ENSG00000223972.5"; transcript_id "ENST00000456328.2"; gene_biotype "transcribed_unprocessed_pseudogene"; gene_name "DDX11L1"; exon_number "1";',
  'chr1\tHAVANA\tgene\t14404\t29570\t.\t-\t.\tgene_id "ENSG00000227232.5"; gene_biotype "unprocessed_pseudogene"; gene_name "WASH7P";'
)

writeLines(gtf_content, "temp.gtf")