library(Rsamtools)

# 1. Create synthetic GTF file
# We include a start_codon to ensure the automatic P-site mapping algorithm in RiboDiPA succeeds.
gtf_lines <- c(
    'chrIV\tEnsembl\tgene\t553100\t554000\t.\t+\t.\tgene_id "YDR050C"; gene_name "TPI1"; gene_source "ensembl"; gene_biotype "protein_coding";',
    'chrIV\tEnsembl\ttranscript\t553100\t554000\t.\t+\t.\tgene_id "YDR050C"; transcript_id "YDR050C_mRNA"; gene_name "TPI1"; gene_source "ensembl"; gene_biotype "protein_coding"; transcript_name "TPI1_mRNA"; transcript_source "ensembl"; transcript_biotype "protein_coding";',
    'chrIV\tEnsembl\texon\t553100\t554000\t.\t+\t.\tgene_id "YDR050C"; transcript_id "YDR050C_mRNA"; exon_number "1"; gene_name "TPI1"; gene_source "ensembl"; gene_biotype "protein_coding"; transcript_