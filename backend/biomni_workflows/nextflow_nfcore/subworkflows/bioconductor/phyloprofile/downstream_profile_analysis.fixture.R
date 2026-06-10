library(PhyloProfile)

# Load built-in processed profile data as shown in the vignette
data("fullProcessedProfile", package="PhyloProfile")
data("finalProcessedProfile", package="PhyloProfile")

# Save the data frames to the expected input file
save(fullProcessedProfile, finalProcessedProfile, file="processedProfile.RData")