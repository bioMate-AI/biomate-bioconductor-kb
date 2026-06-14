# Real user-style input for VariantAnnotation::filterVcf:
#   chr7-sub.vcf.gz (+ .tbi) - a bgzip-compressed, Tabix-indexed somatic VCF from
#   a tumor/normal caller (e.g. MuTect2). It carries:
#     * INFO annotations the prefilters string-match on (some variants tagged
#       "Germline", some carry a "dbsnp" source) so the fast prefilter step
#       actually removes records;
#     * a per-sample AD (allelic depth) FORMAT field for TUMOR and NORMAL so the
#       allelicDepth() filter (which reads geno(x)$AD[,tumor/normal,]) evaluates.
#   This is the genuine shape a user's somatic VCF has; no package demo data.

suppressPackageStartupMessages({
  library(Rsamtools)
})

# Build a single VCF record. status -> SOMATIC_STATUS INFO; src -> VARSOURCE INFO.
# t_ad / n_ad are c(ref_depth, alt_depth) for TUMOR and NORMAL.
mk <- function(pos, id, ref, alt, status, src, t_ad, n_ad) {
  info <- sprintf("SOMATIC_STATUS=%s;VARSOURCE=%s", status, src)
  fmt  <- "GT:AD:DP"
  tum  <- sprintf("0/1:%d,%d:%d", t_ad[1], t_ad[2], sum(t_ad))
  nor  <- sprintf("0/0:%d,%d:%d", n_ad[1], n_ad[2], sum(n_ad))
  sprintf("7\t%d\t%s\t%s\t%s\t.\tPASS\t%s\t%s\t%s\t%s",
          pos, id, ref, alt, info, fmt, tum, nor)
}

header <- c(
  "##fileformat=VCFv4.2",
  "##INFO=<ID=SOMATIC_STATUS,Number=1,Type=String,Description=\"Somatic classification\">",
  "##INFO=<ID=VARSOURCE,Number=1,Type=String,Description=\"Annotation source\">",
  "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">",
  "##FORMAT=<ID=AD,Number=R,Type=Integer,Description=\"Allelic depths for ref and alt\">",
  "##FORMAT=<ID=DP,Number=1,Type=Integer,Description=\"Read depth\">",
  "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tTUMOR\tNORMAL"
)

records <- c(
  mk(50300078, "var1",  "A",  "G", "somatic",  "novel", c(40, 35), c(60, 1)),
  mk(50301010, "var2",  "C",  "T", "somatic",  "novel", c(50, 22), c(70, 0)),
  mk(50302500, "var3",  "G",  "A", "somatic",  "novel", c(33, 40), c(58, 2)),
  mk(50303300, "var4",  "T",  "C", "Germline", "novel", c(45, 44), c(40, 41)),
  mk(50304400, "rs999", "A",  "T", "somatic",  "dbsnp", c(30, 25), c(55, 1)),
  mk(50305500, "var6",  "C",  "G", "somatic",  "novel", c(70, 12), c(80, 0)),
  mk(50306600, "var7",  "AT", "A", "somatic",  "novel", c(40, 30), c(60, 0))
)

writeLines(c(header, records), "chr7-sub.vcf")
bgzip("chr7-sub.vcf", "chr7-sub.vcf.gz", overwrite = TRUE)
indexTabix("chr7-sub.vcf.gz", format = "vcf")
unlink("chr7-sub.vcf")
