library(SeqVarTools)
vcffile <- seqExampleFileName("vcf")
gdsfile <- "gdsfile.gds"
seqVCF2GDS(vcffile, gdsfile, verbose=FALSE)