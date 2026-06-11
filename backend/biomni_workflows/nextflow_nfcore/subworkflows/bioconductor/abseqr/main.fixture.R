library(abseqR)

# Find the provided data that comes installed with abseqR
exdata <- system.file("extdata", "ex", package = "abseqR")

# Create the dataPath directory in the current working directory
dir.create("dataPath", showWarnings = FALSE)

# Copy the contents of the example data to dataPath
# This will include the "auxiliary" directory required by abseqR
file.copy(list.files(exdata, full.names = TRUE), "dataPath", recursive = TRUE)