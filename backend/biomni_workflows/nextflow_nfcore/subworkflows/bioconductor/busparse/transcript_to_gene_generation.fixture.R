library(BUSpaRse)

# Create a synthetic transcriptome.fasta
fasta_content <- c(
  ">ENST00000434970.2 cdna chromosome:GRCh38:14:22438547:22438554:1 gene:ENSG00000237235.2 gene_biotype:TR_D_gene transcript_biotype:TR_D_gene gene_symbol:TRDD2 description:T cell receptor delta diversity 2",
  "ACTG",
  ">ENST00000415118.1 cdna chromosome:GRCh38:14:22438554:22438560:1 gene:ENSG00000223997.1 gene_biotype:TR_D_gene transcript_biotype:TR_D_gene gene_symbol:TRDD1 description:T cell receptor delta diversity 1",
  "CGTA",
  ">ENST00000448914.1 cdna chromosome:GRCh38:14:22438560:22438570:1 gene:ENSG00000228985.1 gene_biotype:TR_D_gene transcript_biotype:TR_D_gene gene_symbol:TRDD3 description:T cell receptor delta diversity 3",
  "ATGC"
)
writeLines(fasta_content, "transcriptome.fasta")

# Create a synthetic annotation.gtf
gtf_content <- c(
  '14\tensembl\tgene\t22438547\t22438554\t.\t+\t.\tgene_id "ENSG00000237235.2"; gene_version "2"; gene_name "TRDD2"; gene_source "ensembl"; gene_biotype "TR_D_gene";',
  '14\tensembl\ttranscript\t22438547\t22438554\t.\t+\t.\tgene_id "ENSG00000237235.2"; gene_version "2"; transcript_id "ENST00000434970.2"; transcript_version "2"; gene_name "TRDD2"; gene_source "ensembl"; gene_biotype "TR_D_gene"; transcript_name "TRDD2-201"; transcript_source "ensembl"; transcript_biotype "TR_D_gene";',
  '14\tensembl\texon\t22438547\t22438554\t.\t+\t.\tgene_id "ENSG00000237235.2"; gene_version "2"; transcript_id "ENST00000434970.2"; transcript_version "2"; exon_number "1"; gene_name "TRDD2"; gene_source "ensembl"; gene_biotype "TR_D_gene"; transcript_name "TRDD2-201"; transcript_source "ensembl"; transcript_biotype "TR_D_gene"; exon_id "ENSE00001700000.1"; exon_version "1";',
  '14\tensembl\tgene\t22438554\t22438560\t.\t+\t.\tgene_id "ENSG00000223997.1"; gene_version "1"; gene_name "TRDD1"; gene_source "ensembl"; gene_biotype "TR_D_gene";',
  '14\tensembl\ttranscript\t22438554\t22438560\t.\t+\t.\tgene_id "ENSG00000223997.1"; gene_version "1"; transcript_id "ENST00000415118.1"; transcript_version "1"; gene_name "TRDD1"; gene_source "ensembl"; gene_biotype "TR_D_gene"; transcript_name "TRDD1-201"; transcript_source "ensembl"; transcript_biotype "TR_D_gene";',
  '14\tensembl\texon\t22438554\t22438560\t.\t+\t.\tgene_id "ENSG00000223997.1"; gene_version "1"; transcript_id "ENST00000415118.1"; transcript_version "1"; exon_number "1"; gene_name "TRDD1"; gene_source "ensembl"; gene_biotype "TR_D_gene"; transcript_name "TRDD1-201"; transcript_source "ensembl"; transcript_biotype "TR_D_gene"; exon_id "ENSE00001700001.1"; exon_version "1";',
  '14\tensembl\tgene\t22438560\t22438570\t.\t+\t.\tgene_id "ENSG00000228985.1"; gene_version "1"; gene_name "TRDD3"; gene_source "ensembl"; gene_biotype "TR_D_gene";',
  '14\tensembl\ttranscript\t22438560\t22438570\t.\t+\t.\tgene_id "ENSG00000228985.1"; gene_version "1"; transcript_id "ENST00000448914.1"; transcript_version "1"; gene_name "TRDD3"; gene_source "ensembl"; gene_biotype "TR_D_gene"; transcript_name "TRDD3-201"; transcript_source "ensembl"; transcript_biotype "TR_D_gene";',
  '14\tensembl\texon\t22438560\t22438570\t.\t+\t.\tgene_id "ENSG00000228985.1"; gene_version "1"; transcript_id "ENST00000448914.1"; transcript_version "1"; exon_number "1"; gene_name "TRDD3"; gene_source "ensembl"; gene_biotype "TR_D_gene"; transcript_name "TRDD3-201"; transcript_source "ensembl"; transcript_biotype "TR_D_gene"; exon_id "ENSE00001700002.1"; exon_version "1";'
)
writeLines(gtf_content, "annotation.gtf")