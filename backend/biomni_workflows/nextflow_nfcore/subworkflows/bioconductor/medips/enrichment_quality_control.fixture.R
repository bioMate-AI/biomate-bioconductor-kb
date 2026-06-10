library(MEDIPS)
library(BSgenome.Hsapiens.UCSC.hg19)
library(MEDIPSData)

bam_source <- system.file("extdata", "hESCs.MeDIP.Rep1.chr22.bam", package="MEDIPSData")

if (file.exists(bam_source)) {
    file.copy(bam_source, "bam.file.hESCs.Rep1.MeDIP", overwrite = TRUE)
} else {
    stop("Required BAM file not found in MEDIPSData package.")
}