library(SeqVarTools)
vcffile <- seqExampleFileName("vcf")
gdsfile <- "file.gds"
seqVCF2GDS(vcffile, gdsfile, verbose=FALSE)