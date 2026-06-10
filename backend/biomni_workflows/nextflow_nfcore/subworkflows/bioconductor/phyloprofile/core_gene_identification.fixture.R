library(PhyloProfile)

# Load built-in data from the package
data("fullProcessedProfile", package="PhyloProfile")

# Assign to the expected object name
processed_profile <- fullProcessedProfile

# Save to the required input file
save(processed_profile, file="processed_profile.RData")