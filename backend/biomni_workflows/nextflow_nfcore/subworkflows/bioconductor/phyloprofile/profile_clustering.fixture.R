library(PhyloProfile)

# Load built-in datasets from the package as demonstrated in the vignette
data("finalProcessedProfile", package="PhyloProfile")
data("fullProcessedProfile", package="PhyloProfile")
data("mainLongRaw", package="PhyloProfile")

# Create an alias to match the requested file name just in case the workflow expects it
processed_profile <- fullProcessedProfile

# Serialize the objects to the required input file
save(finalProcessedProfile, fullProcessedProfile, mainLongRaw, processed_profile, file="processed_profile.RData")