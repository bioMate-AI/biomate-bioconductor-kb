library(SNPRelate)
library(gdsfmt)

# 1. Create test.gds as shown in the vignette
data(hapmap_geno)
snpgdsCreateGeno("test.gds", genmat = hapmap_geno$genotype,
    sample.id = hapmap_geno$sample.id,
    snp.id = hapmap_geno$snp.id,
    snp.chromosome = hapmap_geno$snp.chromosome,
    snp.position = hapmap_geno$snp.position,
    snp.allele = hapmap_geno$snp.allele,
    snpfirstdim=TRUE)

# 2. Provide bed.fn, fam.fn, bim.fn, vcf.fn from the package's extdata
extdata_dir <- system.file("extdata", package="SNPRelate")

bed_file <- list.files(extdata_dir, pattern="\\.bed$", full.names=TRUE)[1]
fam_file <- list.files(extdata_dir, pattern="\\.fam$", full.names=TRUE)[1]
bim_file <- list.files(extdata_dir, pattern="\\.bim$", full.names=TRUE)[1]
vcf_file <- list.files(extdata_dir, pattern="\\.vcf$|\\.vcf\\.gz$", full.names=TRUE)[1]

# Copy or synthesize bed.fn
if (!is.na(bed_file) && file.exists(bed_file)) {
    file.copy(bed_file, "bed.fn")
} else {
    writeBin(as.raw(c(0x6c, 0x1b, 0x01)), "bed.fn")
}

# Copy or synthesize fam.fn
if (!is.na(fam_file) && file.exists(fam_file)) {
    file.copy(fam_file, "fam.fn")
} else {
    write.table(data.frame(F1="F1", I1="I1", P=0, M=0, Sex=1, Pheno=1), 
                "fam.fn", row.names=FALSE, col.names=FALSE, quote=FALSE)
}

# Copy or synthesize bim.fn
if (!is.na(bim_file) && file.exists(bim_file)) {
    file.copy(bim_file, "bim.fn")
} else {
    write.table(data.frame(Chr=1, SNP="rs1", cM=0, Pos=100, A1="A", A2="G"), 
                "bim.fn", row.names=FALSE, col.names=FALSE, quote=FALSE)
}

# Copy or synthesize vcf.fn
if (!is.na(vcf_file) && file.exists(vcf_file)) {
    file.copy(vcf_file, "vcf.fn")
} else {
    writeLines(c("##fileformat=VCFv4.2", 
                 "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tSAMP1", 
                 "1\t100\trs1\tA\tG\t.\tPASS\t.\tGT\t0/1"), 
               "vcf.fn")
}