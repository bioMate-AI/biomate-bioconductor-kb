library(Mergeomics)

# Helper function to copy existing package files or create synthetic ones if missing
copy_or_create <- function(filename, synthetic_data) {
    src <- system.file("extdata", filename, package="Mergeomics")
    if (src != "" && file.exists(src)) {
        file.copy(src, filename, overwrite = TRUE)
    } else {
        write.table(synthetic_data, filename, sep = "\t", row.names = FALSE, quote = FALSE)
    }
}

# 1. Significant_pathways.txt
moddata_synth <- data.frame(
    MODULE = c("Mod1", "Mod1", "Mod2", "Mod2"),
    GENE = c("GeneA", "GeneB", "GeneC", "GeneD"),
    stringsAsFactors = FALSE
)
copy_or_create("Significant_pathways.txt", moddata_synth)

# 2. Significant_pathways.info.txt
modinfo_synth <- data.frame(
    MODULE = c("Mod1", "Mod2"),
    SOURCE = c("Source1", "Source2"),
    DESCR = c("Description 1", "Description 2"),
    stringsAsFactors = FALSE
)
copy_or_create("Significant_pathways.info.txt", modinfo_synth)

# 3. symbols.txt
syms_synth <- data.frame(
    HUMAN = c("GeneA", "GeneB", "GeneC", "GeneD"),
    MOUSE = c("M_GeneA", "M_GeneB", "M_GeneC", "M_GeneD"),
    stringsAsFactors = FALSE
)
copy_or_create("symbols.txt", syms_synth)