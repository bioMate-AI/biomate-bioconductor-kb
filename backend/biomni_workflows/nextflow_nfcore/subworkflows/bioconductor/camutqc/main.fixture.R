# Real user-style input for CaMutQC single-sample VCF filtering + TMB:
#   WES_EA_T_1_mutect2.vep.vcf - a VEP-annotated, MuTect2-style somatic VCF for a
#       tumour/normal pair. It carries the CSQ INFO field (with the VEP
#       "Format: Allele|Consequence|...|SYMBOL|Gene|...|BIOTYPE|..." header that
#       vcfToMAF parses) and per-sample AD/DP/RD genotype fields. Gene IDs are
#       real Ensembl gene IDs (so CaMutQC's ENSEMBL->ENTREZID mapping resolves).
#   PON_test.txt              - a panel-of-normals table (chrom/pos of recurrent
#       technical artefacts to filter out).
#   Pan-cancer-hg38.bed       - the captured/target regions (BED: chrom/start/end)
#       used to compute the TMB denominator (Mb of sequenced territory).
# These are exactly the three inputs a user feeds CaMutQC; no package demo data.

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

# CHROM uses the "chr" prefix so the MAF Chromosome matches CaMutQC's BED handling
# (readBed normalises bed contigs to chr-prefixed and filters to chr1..chrY).
variants <- list(
    list(chr="chr7", pos=140453136, ref="A", alt="T", sym="BRAF",  gene="ENSG00000157764",
         conseq="missense_variant",   t_ad=c(60,40), n_ad=c(80,0)),
    list(chr="chr12", pos=25245350, ref="C", alt="A", sym="KRAS",  gene="ENSG00000133703",
         conseq="missense_variant",   t_ad=c(55,35), n_ad=c(70,1)),
    list(chr="chr17", pos=7674220, ref="G", alt="A", sym="TP53",   gene="ENSG00000141510",
         conseq="stop_gained",        t_ad=c(45,50), n_ad=c(60,0)),
    list(chr="chr3", pos=179234297, ref="A", alt="G", sym="PIK3CA",gene="ENSG00000121879",
         conseq="missense_variant",   t_ad=c(50,30), n_ad=c(75,2)),
    list(chr="chr7", pos=55191822, ref="T", alt="G", sym="EGFR",   gene="ENSG00000146648",
         conseq="synonymous_variant", t_ad=c(40,25), n_ad=c(65,0)),
    list(chr="chr10", pos=87894077, ref="C", alt="T", sym="PTEN",  gene="ENSG00000171862",
         conseq="missense_variant",   t_ad=c(48,42), n_ad=c(70,1))
)

header <- c(
    "##fileformat=VCFv4.2",
    "##reference=GRCh38",
    "##tumor_sample=WES_EA_T_1",
    "##normal_sample=WES_EA_N_1",
    "##FILTER=<ID=PASS,Description=\"All filters passed\">",
    "##INFO=<ID=AS_FilterStatus,Number=A,Type=String,Description=\"Filter status\">",
    sprintf("##INFO=<ID=CSQ,Number=.,Type=String,Description=\"Consequence annotations from Ensembl VEP. Format: %s\">", csq_fmt),
    "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">",
    "##FORMAT=<ID=AD,Number=R,Type=Integer,Description=\"Allelic depths for ref and alt\">",
    "##FORMAT=<ID=DP,Number=1,Type=Integer,Description=\"Read depth\">",
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tWES_EA_T_1\tWES_EA_N_1"
)

# MuTect2-style FORMAT (GT:AD:DP, AD = ref,alt) -- this is the layout CaMutQC's
# vcfToMAF parses when no separate RD field is present.
rec <- vapply(variants, function(v) {
    csq <- mk_csq(v$alt, v$conseq, v$sym, v$gene)
    info <- sprintf("AS_FilterStatus=PASS;CSQ=%s", csq)
    fmt  <- "GT:AD:DP"
    tum  <- sprintf("0/1:%d,%d:%d", v$t_ad[1], v$t_ad[2], sum(v$t_ad))
    nor  <- sprintf("0/0:%d,%d:%d", v$n_ad[1], v$n_ad[2], sum(v$n_ad))
    sprintf("%s\t%d\t.\t%s\t%s\t.\tPASS\t%s\t%s\t%s\t%s",
            v$chr, v$pos, v$ref, v$alt, info, fmt, tum, nor)
}, character(1))

writeLines(c(header, rec), "WES_EA_T_1_mutect2.vep.vcf")

# --- Panel of normals (recurrent technical artefacts) -------------------------
# CaMutQC's txt PON is merged onto the MAF by CHROM/POS/REF/ALT, so the columns
# must be named exactly CHROM, POS, REF, ALT (header = TRUE). A few recurrent
# artefact sites that are NOT among the somatic calls above (so nothing is
# wrongly removed, but the PON filter genuinely runs).
pon <- data.frame(
    CHROM = c("1", "2", "5"),
    POS   = as.integer(c(100000L, 200000L, 300000L)),
    REF   = c("A", "C", "G"),
    ALT   = c("G", "T", "A"),
    stringsAsFactors = FALSE
)
write.table(pon, "PON_test.txt", sep = "\t", quote = FALSE, row.names = FALSE)

# --- Target regions for TMB denominator (BED: chrom, start, end) --------------
# readBed requires >=3 columns with INTEGER start/end. A few-Mb capture panel
# across the chromosomes carrying the variants above.
bed <- data.frame(
    chrom = c("chr3", "chr7", "chr7", "chr10", "chr12", "chr17"),
    start = as.integer(c(179000000L, 55000000L, 140000000L, 87000000L, 25000000L, 7600000L)),
    end   = as.integer(c(179500000L, 55500000L, 140500000L, 87500000L, 25500000L, 7700000L)),
    stringsAsFactors = FALSE
)
write.table(bed, "Pan-cancer-hg38.bed", sep = "\t", quote = FALSE,
            row.names = FALSE, col.names = FALSE)
