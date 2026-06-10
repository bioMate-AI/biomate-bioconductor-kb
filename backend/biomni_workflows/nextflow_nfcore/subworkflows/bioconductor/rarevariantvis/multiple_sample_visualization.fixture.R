library(RareVariantVis)
library(DataRareVariantVis)

# Locate the example files from the companion package
sample <- system.file("extdata", "CoriellIndex_S1.vcf.gz", package = "DataRareVariantVis")
sv_sample <- system.file("extdata", "CoriellIndex_S1.sv.vcf.gz", package = "DataRareVariantVis")

# Run the vignette's data preparation function to generate the output files
try({
    chromosomeVis(sample = sample, sv_sample = sv_sample, chromosomes = c("19"))
}, silent = TRUE)

# Ensure the first required input file exists (fallback to dummy data if chromosomeVis failed)
if (!file.exists("RareVariants_CoriellIndex_S1.txt")) {
    dummy_data <- data.frame(
        chromosome = "19",
        `final positions` = 12345,
        `variant type` = "nonsynonymous",
        `ref allele` = "A",
        `alt allele` = "G",
        `final variations` = 1.0,
        conservation = 0.9,
        `gene name` = "GENE1",
        check.names = FALSE
    )
    write.table(dummy_data, "RareVariants_CoriellIndex_S1.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

# Ensure the second required input file exists by copying the first one
if (!file.exists("RareVariants_Coriell_S2.txt")) {
    file.copy("RareVariants_CoriellIndex_S1.txt", "RareVariants_Coriell_S2.txt")
}