library(katdetectr)

# Generate synthetic genomic variants including kataegis foci as shown in the vignette
syntheticData <- generateSyntheticData(nBackgroundVariants = 2500, nKataegisFoci = 1)

# Serialize the VRanges object to the exact file expected by the workflow
saveRDS(syntheticData, file = "syntheticData")