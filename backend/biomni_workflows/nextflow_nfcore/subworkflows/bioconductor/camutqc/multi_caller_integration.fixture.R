# Real user-style input for CaMutQC multi-caller integration:
#   Three VEP-annotated somatic VCFs from three callers on the SAME tumor/normal
#   pair (MuSE, VarScan2, Mutect2), plus a panel-of-normals text file. These are
#   exactly the inputs CaMutQC's vcfToMAF()/mutFilterCom()/processMut("union")
#   pipeline consumes: paired-sample VCFs whose INFO carries an Ensembl-VEP `CSQ`
#   annotation (Allele|Consequence|IMPACT|SYMBOL|Gene|...), with per-sample
#   GT:AD:DP genotype fields.
#
# The variants are synthetic but biologically well-formed: real human Ensembl gene
# IDs / HGNC symbols, exonic missense consequences, high tumor/normal depth and
# tumor VAF (so they pass CaMutQC's default technical+population filters), no
# population-frequency / dbSNP annotation (clean somatic calls), FILTER=PASS. This
# is the genuine multi-caller somatic-VCF contract — no package demo data, no
# system.file().
set.seed(20260615)

# --- Shared tumor/normal somatic variants (subset overlaps across callers). ---
# Real Ensembl gene/symbol pairs (well-known cancer genes), all on coding exons.
variants <- data.frame(
  chrom  = c("chr3",            "chr17",           "chr12",           "chr7",            "chr5",            "chr10"),
  pos    = c(178936091L,        7577120L,          25245350L,         140453136L,        112173917L,        89692905L),
  ref    = c("G",               "C",               "C",               "A",               "C",               "T"),
  alt    = c("A",               "T",               "A",               "T",               "T",               "A"),
  gene   = c("ENSG00000121879", "ENSG00000141510", "ENSG00000133703", "ENSG00000157764", "ENSG00000134982", "ENSG00000171862"),
  symbol = c("PIK3CA",          "TP53",            "KRAS",            "BRAF",            "APC",             "PTEN"),
  enst   = c("ENST00000263967", "ENST00000269305", "ENST00000256078", "ENST00000288602", "ENST00000257430", "ENST00000371953"),
  stringsAsFactors = FALSE
)

csq_format <- paste(
  "Allele","Consequence","IMPACT","SYMBOL","Gene","Feature_type","Feature",
  "BIOTYPE","EXON","INTRON","HGVSc","HGVSp","cDNA_position","CDS_position",
  "Protein_position","Amino_acids","Codons","Existing_variation","DISTANCE",
  "STRAND","FLAGS","SYMBOL_SOURCE","HGNC_ID","SOURCE","AF","gnomADe_AF",
  "gnomADg_AF","MAX_AF","MAX_AF_POPS","CLIN_SIG","SOMATIC","PHENO",
  sep = "|")

# One CSQ entry (single, best transcript) per variant. Most fields blank (a clean
# somatic call with no population annotation), matching real VEP output for novel
# somatic variants. Field order MUST match csq_format above.
make_csq <- function(v, i) {
  fields <- rep("", 32)
  fields[1]  <- v$alt[i]                    # Allele
  fields[2]  <- "missense_variant"          # Consequence
  fields[3]  <- "MODERATE"                  # IMPACT
  fields[4]  <- v$symbol[i]                 # SYMBOL  -> Hugo_Symbol
  fields[5]  <- v$gene[i]                   # Gene    -> ENSEMBL (bitr -> ENTREZ)
  fields[6]  <- "Transcript"                # Feature_type
  fields[7]  <- v$enst[i]                   # Feature
  fields[8]  <- "protein_coding"            # BIOTYPE
  fields[9]  <- "5/10"                      # EXON
  fields[13] <- as.character(100 + i)       # cDNA_position
  fields[14] <- as.character(100 + i)       # CDS_position
  fields[15] <- as.character(34 + i)        # Protein_position
  fields[16] <- "E/K"                       # Amino_acids
  fields[17] <- "Gag/Aag"                   # Codons
  fields[20] <- "1"                         # STRAND
  fields[22] <- "HGNC"                      # SYMBOL_SOURCE
  paste(fields, collapse = "|")
}

# Header lines common to all three callers (paired tumor/normal, GRCh38).
common_header <- function(tumor, normal) c(
  "##fileformat=VCFv4.2",
  sprintf("##tumor_sample=%s", tumor),
  sprintf("##normal_sample=%s", normal),
  "##reference=GRCh38",
  '##FILTER=<ID=PASS,Description="All filters passed">',
  '##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">',
  '##FORMAT=<ID=AD,Number=R,Type=Integer,Description="Allelic depths">',
  '##FORMAT=<ID=DP,Number=1,Type=Integer,Description="Read depth">',
  '##INFO=<ID=DP,Number=1,Type=Integer,Description="Total depth">',
  sprintf('##INFO=<ID=CSQ,Number=.,Type=String,Description="Consequence annotations from Ensembl VEP. Format: %s">', csq_format),
  "##contig=<ID=chr3,length=198295559>",
  "##contig=<ID=chr17,length=83257441>",
  "##contig=<ID=chr12,length=133275309>",
  "##contig=<ID=chr7,length=159345973>",
  "##contig=<ID=chr5,length=181538259>",
  "##contig=<ID=chr10,length=133797422>"
)

TUMOR  <- "WES_EA_T_1"
NORMAL <- "WES_EA_N_1"

# Write a caller VCF for the variant rows in `rows`. High, clean depths so the
# variants survive CaMutQC's default filters (tumorDP>=20, normalDP>=10,
# tumorAD>=5, VAF>=0.05). Normal is hom-ref (somatic).
write_caller_vcf <- function(path, rows) {
  hdr <- common_header(TUMOR, NORMAL)
  col_hdr <- sprintf("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t%s\t%s",
                     NORMAL, TUMOR)
  body <- character(0)
  for (i in rows) {
    csq <- make_csq(variants, i)
    info <- sprintf("DP=120;CSQ=%s", csq)
    t_ad_ref <- 70L; t_ad_alt <- 50L; t_dp <- t_ad_ref + t_ad_alt   # VAF ~0.42
    n_ad_ref <- 60L; n_ad_alt <- 0L;  n_dp <- n_ad_ref + n_ad_alt
    normal_fmt <- sprintf("0/0:%d,%d:%d", n_ad_ref, n_ad_alt, n_dp)
    tumor_fmt  <- sprintf("0/1:%d,%d:%d", t_ad_ref, t_ad_alt, t_dp)
    row <- sprintf("%s\t%d\t.\t%s\t%s\t.\tPASS\t%s\tGT:AD:DP\t%s\t%s",
                   variants$chrom[i], variants$pos[i], variants$ref[i],
                   variants$alt[i], info, normal_fmt, tumor_fmt)
    body <- c(body, row)
  }
  writeLines(c(hdr, col_hdr, body), path)
}

# Each caller reports an overlapping-but-distinct set of the somatic variants
# (the realistic scenario the union step is designed for).
write_caller_vcf("WES_EA_T_1.MuSE.vep.vcf",                 c(1, 2, 3, 4))
write_caller_vcf("WES_EA_T_1_varscan_filter_snp.vep.vcf",   c(1, 2, 3, 5))
write_caller_vcf("WES_EA_T_1_mutect2.vep.vcf",              c(1, 2, 4, 6))

# --- Panel-of-normals (txt format CaMutQC reads via PONformat="txt"). CaMutQC
#     merges it against the MAF on CHROM/POS/REF/ALT, so the header MUST be exactly
#     CHROM POS REF ALT. These are recurrent-artifact sites; NONE match our somatic
#     variants, so the PoN filter keeps every somatic call. ---
pon <- data.frame(
  CHROM = c("chr1",    "chr2",    "chr19",  "chrX"),
  POS   = c(1000000L,  2000000L,  500000L,  750000L),
  REF   = c("A",       "G",       "C",      "T"),
  ALT   = c("T",       "C",       "G",      "A"),
  stringsAsFactors = FALSE
)
write.table(pon, "PON_test.txt", sep = "\t", row.names = FALSE,
            col.names = TRUE, quote = FALSE)
