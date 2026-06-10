suppressPackageStartupMessages(library(isobar))

# Load the example IBSpectra dataset provided by the package
data(ibspiked_set1)

# Convert to a data.frame and subset to keep the test fixture small and fast
df <- as.data.frame(ibspiked_set1)
df <- head(df, 100)

# 1. Write the peptide identification file
# The vignette demonstrates writing IBSpectra to a tabular format using tab separation
write.table(df, file = "identifications.id.csv", sep = "\t", row.names = FALSE, quote = FALSE)

# 2. Write the MS2 peaklist file (MGF format)
# We construct a synthetic MGF that perfectly matches the spectra in the ID file.
# We use the exact reporter tag masses expected for this iTRAQ multiplex.
masses <- reporterTagMasses(ibspiked_set1)
spectra_names <- unique(df$spectrum)

mgf_lines <- unlist(lapply(spectra_names, function(s) {
    # Create peak lines for each reporter ion with a dummy intensity of 1000.0
    peaks <- paste(sprintf("%.4f", masses), "1000.0")
    
    c("BEGIN IONS",
      paste0("TITLE=", s),
      "PEPMASS=400.0",
      "CHARGE=2+",
      peaks,
      "END IONS",
      "")
}))

writeLines(mgf_lines, "peaklist.mgf")

# Verify files were created successfully
stopifnot(file.exists("identifications.id.csv"))
stopifnot(file.exists("peaklist.mgf"))