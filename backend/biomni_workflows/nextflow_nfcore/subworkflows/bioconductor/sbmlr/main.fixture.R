library(SBMLR)

# Read the example model from the package
curto <- readSBML(system.file("models", "curto.xml", package = "SBMLR"))

# Save it as the expected input file
saveSBML(curto, "model.xml")