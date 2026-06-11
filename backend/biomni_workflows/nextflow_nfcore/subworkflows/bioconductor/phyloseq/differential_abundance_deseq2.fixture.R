library("phyloseq")

# Load the Global Patterns dataset included in the phyloseq package
data(GlobalPatterns)

# Prune OTUs that are not present in at least one sample
GP <- prune_taxa(taxa_sums(GlobalPatterns) > 0, GlobalPatterns)

# Define a human-associated versus non-human categorical variable:
human <- get_variable(GP, "SampleType") %in% c("Feces", "Mock", "Skin", "Tongue")

# Add new human variable to sample data:
sample_data(GP)$human <- factor(human)

# Serialize the assembled phyloseq S4 object to the expected input file
saveRDS(GP, "phyloseq_object")