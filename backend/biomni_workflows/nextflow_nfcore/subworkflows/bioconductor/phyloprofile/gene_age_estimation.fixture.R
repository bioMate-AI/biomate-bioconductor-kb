library(PhyloProfile)

data("fullProcessedProfile", package="PhyloProfile")
data("finalProcessedProfile", package="PhyloProfile")
data("mainLongRaw", package="PhyloProfile")

processed_profile <- fullProcessedProfile
save(processed_profile, fullProcessedProfile, finalProcessedProfile, mainLongRaw, file="processed_profile.RData")