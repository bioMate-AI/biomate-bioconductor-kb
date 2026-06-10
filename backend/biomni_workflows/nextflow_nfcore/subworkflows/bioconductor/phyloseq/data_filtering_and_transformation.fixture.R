library("phyloseq")

data(GlobalPatterns)

# prune OTUs that are not present in at least one sample
GP <- prune_taxa(taxa_sums(GlobalPatterns) > 0, GlobalPatterns)

# Define a human-associated versus non-human categorical variable:
human <- get_variable(GP, "SampleType") %in% c("Feces", "Mock", "Skin", "Tongue")

# Add new human variable to sample data:
sample_data(GP)$human <- factor(human)

# Save the phyloseq object to the expected file
saveRDS(GP, "phyloseq_object")