library("flowcatchR")
library("EBImage")

# Load the example dataset from the flowcatchR package
data("MesenteriumSubset", package = "flowcatchR")

# Create the expected input directory
dir.create("image.files", showWarnings = FALSE)

# The MesenteriumSubset is a Frames object (extending Image) with 20 frames.
# We write each frame as a PNG file into the image.files directory.
files <- file.path("image.files", sprintf("frame_%02d.png", 1:20))
writeImage(MesenteriumSubset, files)