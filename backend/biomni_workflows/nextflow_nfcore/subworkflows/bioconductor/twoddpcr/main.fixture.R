library(twoddpcr)
library(ggplot2)
library(reshape2)

# Create the required input directory
dir.create("data/amplitudes", recursive = TRUE, showWarnings = FALSE)

# The vignette uses the in-built KRASdata dataset.
# We serialize this list of data.frames into the directory as CSV files
# to simulate the raw droplet amplitude CSV files exported from QuantaSoft.
for (well in names(KRASdata)) {
    file_path <- file.path("data/amplitudes", paste0(well, "_Amplitude.csv"))
    write.csv(KRASdata[[well]], file = file_path, row.names = FALSE, quote = FALSE)
}