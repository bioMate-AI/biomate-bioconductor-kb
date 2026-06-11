library(planttfhunter)
library(Biostrings)

# Load example data from the package
data(gsu, package = "planttfhunter")

# Simulate 4 different species by sampling 50 random genes from `gsu` 4 times
set.seed(123)
proteomes <- list(
  Gsu1 = gsu[sample(names(gsu), 50, replace = FALSE)],
  Gsu2 = gsu[sample(names(gsu), 50, replace = FALSE)],
  Gsu3 = gsu[sample(names(gsu), 50, replace = FALSE)],
  Gsu4 = gsu[sample(names(gsu), 50, replace = FALSE)]
)

# Create the required proteomes_directory and write FASTA files
dir.create("proteomes_directory", showWarnings = FALSE)
for (species_name in names(proteomes)) {
  writeXStringSet(
    proteomes[[species_name]], 
    filepath = file.path("proteomes_directory", paste0(species_name, ".fasta"))
  )
}

# Create simulated species metadata
species_metadata <- data.frame(
  row.names = names(proteomes),
  Division = "Rhodophyta",
  Origin = c("US", "Belgium", "China", "Brazil")
)

# Write the required metadata.csv
write.csv(species_metadata, file = "metadata.csv", row.names = TRUE)