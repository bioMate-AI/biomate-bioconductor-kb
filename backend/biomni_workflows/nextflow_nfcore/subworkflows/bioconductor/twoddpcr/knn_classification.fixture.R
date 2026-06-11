library(twoddpcr)

# Load the in-built dataset
data("KRASdata", package = "twoddpcr")

# Create the target directory for the input files
dir.create("data/amplitudes", recursive = TRUE, showWarnings = FALSE)

# Write each well's data to a CSV file in the directory to simulate QuantaSoft output
for (well_name in names(KRASdata)) {
    file_path <- file.path("data/amplitudes", paste0(well_name, "_Amplitude.csv"))
    write.csv(KRASdata[[well_name]], file = file_path, row.names = FALSE)
}