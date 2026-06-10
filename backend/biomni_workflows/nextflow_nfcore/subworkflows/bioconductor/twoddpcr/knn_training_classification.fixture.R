library(twoddpcr)

# Create the required input directory
dir.create("data/amplitudes", recursive = TRUE, showWarnings = FALSE)

# Load the in-built dataset used in the vignette
data("KRASdata", package = "twoddpcr")

# The workflow reads from data/amplitudes, which typically contains 
# QuantaSoft exported CSV files for each well.
# We serialize the KRASdata list of data.frames into CSV files in this directory.
for (well_name in names(KRASdata)) {
    file_path <- file.path("data/amplitudes", paste0(well_name, "_Amplitude.csv"))
    write.csv(KRASdata[[well_name]], file = file_path, row.names = FALSE, quote = FALSE)
}