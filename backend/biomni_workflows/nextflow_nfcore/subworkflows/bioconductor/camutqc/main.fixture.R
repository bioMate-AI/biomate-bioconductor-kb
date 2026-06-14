# Real user-style input for CaMutQC single-sample VCF filtering + TMB:
#   WES_EA_T_1_mutect2.vep.vcf - a VEP-annotated, MuTect2-style somatic VCF for a
#       tumour/normal pair. It carries the CSQ INFO field (with the VEP
#       "Format: Allele|Consequence|...|SYMBOL|Gene|...|BIOTYPE|..." header that
#       vcfToMAF parses) and per-sample AD/DP/RD genotype fields. Gene IDs are
#       real Ensembl gene IDs (so CaMutQC's ENSEMBL->ENTREZID mapping resolves).
#   PON_test.txt              - a panel-of-normals table (chrom/pos of recurrent
#       technical artefacts to filter out).
#   Pan-cancer-hg38.rds       - the captured/target regions (GRanges) used to
#       compute the TMB denominator (Mb of sequenced territory).
# These are exactly the three inputs a user feeds CaMutQC; no package demo data.

suppressPackageStartupMessages(library(GenomicRanges))

# --- VEP-annotated somatic VCF ------------------------------------------------
csq_fields <- c("Allele", "Consequence", "IMPACT", "SYMBOL", "Gene",
                "Feature_type", "Feature", "BIOTYPE", "EXON", "INTRON",
                "HGVSc", "HGVSp", "cDNA_position", "CDS_position",
                "Protein_position", "Amino_acids", "Codons",
                "Existing_variation", "STRAND", "CANONICAL")
csq_fmt <- paste(csq_fields, collapse = "|")

# Each variant: real Ensembl gene IDs + protein-coding missense/synonymous etc.
mk_csq <- function(allele, conseq, symbol, gene, biotype = "protein_coding",
                   cdna = "100") {
    vals <- c(allele, conseq, "MODERATE", symbol, gene, "Transcript",
              paste0(gene, "_t1"), biotype, "2/10", "", "c.100A>G",
              "p.Lys34Arg", cdna, "100", "34", "K/R", "aAg/aGg",
              "", "1", "YES")
    paste(vals, collapse = "|")
}

variants <- list(
    list(chr="7", pos=140453136, ref="A", alt="T", sym="BRAF",  gene="ENSG00000157764",
         conseq="missense_variant",   t_ad=c(60,40), n_ad=c(80,0)),
    list(chr="12", pos=25245350, ref="C", alt="A", sym="KRAS",  gene="ENSG00000133703",
         conseq="missense_variant",   t_ad=c(55,35), n_ad=c(70,1)),
    list(chr="17", pos=7674220, ref="G", alt="A", sym="TP53",   gene="ENSG00000141510",
         conseq="stop_gained",        t_ad=c(45,50), n_ad=c(60,0)),
    list(chr="3", pos=179234297, ref="A", alt="G", sym="PIK3CA",gene="ENSG00000121879",
         conseq="missense_variant",   t_ad=c(50,30), n_ad=c(75,2)),
    list(chr="7", pos=55191822, ref="T", alt="G", sym="EGFR",   gene="ENSG00000146648",
         conseq="synonymous_variant", t_ad=c(40,25), n_ad=c(65,0)),
    list(chr="10", pos=87894077, ref="C", alt="T", sym="PTEN",  gene="ENSG00000171862",
         conseq="missense_variant",   t_ad=c(48,42), n_ad=c(70,1))
)

header <- c(
    "##fileformat=VCFv4.2",
    "##tumor_sample=WES_EA_T_1",
    "##normal_sample=WES_EA_N_1",
    "##FILTER=<ID=PASS,Description=\"All filters passed\">",
    "##INFO=<ID=AS_FilterStatus,Number=A,Type=String,Description=\"Filter status\">",
    sprintf("##INFO=<ID=CSQ,Number=.,Type=String,Description=\"Consequence annotations from Ensembl VEP. Format: %s\">", csq_fmt),
    "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">",
    "##FORMAT=<ID=AD,Number=R,Type=Integer,Description=\"Allelic depths\">",
    "##FORMAT=<ID=RD,Number=1,Type=Integer,Description=\"Reference depth\">",
    "##FORMAT=<ID=DP,Number=1,Type=Integer,Description=\"Read depth\">",
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tWES_EA_T_1\tWES_EA_N_1"
)

rec <- vapply(variants, function(v) {
    csq <- mk_csq(v$alt, v$conseq, v$sym, v$gene)
    info <- sprintf("AS_FilterStatus=PASS;CSQ=%s", csq)
    fmt  <- "GT:AD:RD:DP"
    tum  <- sprintf("0/1:%d,%d:%d:%d", v$t_ad[1], v$t_ad[2], v$t_ad[1], sum(v$t_ad))
    nor  <- sprintf("0/0:%d,%d:%d:%d", v$n_ad[1], v$n_ad[2], v$n_ad[1], sum(v$n_ad))
    sprintf("%s\t%d\t.\t%s\t%s\t.\tPASS\t%s\t%s\t%s\t%s",
            v$chr, v$pos, v$ref, v$alt, info, fmt, tum, nor)
}, character(1))

writeLines(c(header, rec), "WES_EA_T_1_mutect2.vep.vcf")

# --- Panel of normals (recurrent technical artefacts) -------------------------
pon <- data.frame(
    Chr = c("1", "2", "5"),
    Start = c(100000, 200000, 300000),
    End = c(100000, 200000, 300000),
    Ref = c("A", "C", "G"),
    Alt = c("G", "T", "A"),
    stringsAsFactors = FALSE
)
write.table(pon, "PON_test.txt", sep = "\t", quote = FALSE, row.names = FALSE)

# --- Target regions for TMB denominator (GRanges) -----------------------------
regions <- GRanges(
    seqnames = c("3", "7", "10", "12", "17"),
    ranges = IRanges(start = c(1, 1, 1, 1, 1),
                     end = c(2e8, 1.6e8, 1.35e8, 1.33e8, 8.3e7))
)
saveRDS(regions, "Pan-cancer-hg38.rds")
