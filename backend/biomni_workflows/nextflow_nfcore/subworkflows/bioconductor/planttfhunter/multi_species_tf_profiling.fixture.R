library(planttfhunter)
library(Biostrings)

data(gsu)

set.seed(123)
proteomes <- list(
    Gsu1 = gsu[sample(names(gsu), 50, replace = FALSE)],
    Gsu2 = gsu[sample(names(gsu), 50, replace = FALSE)],
    Gsu3 = gsu[sample(names(gsu), 50, replace = FALSE)],
    Gsu4 = gsu[sample(names(gsu), 50, replace = FALSE)]
)

dir.create("species_proteomes_directory", showWarnings = FALSE)

for (species_name in names(proteomes)) {
    fasta_file <- file.path("species_proteomes_directory", paste0(species_name, ".fasta"))
    writeXStringSet(proteomes[[species_name]], filepath = fasta_file)
}

species_metadata <- data.frame(
    row.names = names(proteomes),
    Division = "Rhodophyta",
    Origin = c("US", "Belgium", "China", "Brazil")
)

write.csv(species_metadata, file = "species_metadata.csv", row.names = TRUE)