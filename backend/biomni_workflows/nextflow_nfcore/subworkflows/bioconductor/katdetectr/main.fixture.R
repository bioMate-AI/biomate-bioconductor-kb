library(katdetectr)

# 1. pathToVCF
vcf_candidates <- list.files(system.file("extdata", package = "katdetectr"), pattern = "\\.vcf$", full.names = TRUE)
if (length(vcf_candidates) > 0) {
    file.copy(vcf_candidates[1], "pathToVCF")
} else {
    # Fallback dummy VCF
    writeLines(c("##fileformat=VCFv4.2", "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"), "pathToVCF")
}

# 2. pathToMAF
maf_candidates <- list.files(system.file("extdata", package = "katdetectr"), pattern = "\\.maf$", full.names = TRUE)
if (length(maf_candidates) > 0) {
    file.copy(maf_candidates[1], "pathToMAF")
} else {
    # Fallback dummy MAF
    writeLines(c("Hugo_Symbol\tChromosome\tStart_Position\tEnd_Position\tReference_Allele\tTumor_Seq_Allele2\tVariant_Classification\tVariant_Type\tTumor_Sample_Barcode"), "pathToMAF")
}

# 3. syntheticData
syntheticData <- generateSyntheticData(nBackgroundVariants = 2500, nKataegisFoci = 1)
saveRDS(syntheticData, "syntheticData")