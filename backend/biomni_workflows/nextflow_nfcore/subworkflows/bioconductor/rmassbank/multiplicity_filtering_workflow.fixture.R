library(RMassBank)
library(RMassBankData)

# 1. Prepare NarcoticsDataset.csv
csv_path <- system.file("list/NarcoticsDataset.csv", package="RMassBankData")
if (csv_path != "" && file.exists(csv_path)) {
    file.copy(csv_path, "NarcoticsDataset.csv", overwrite = TRUE)
} else {
    # Fallback if the file is not found in the installed package
    df <- data.frame(
        ID = c(2859, 2860),
        Name = c("Cocaine", "Heroin"),
        SMILES = c("CN1C2CCC1C(C(O2)C3=CC=CC=C3)C(=O)OC", "CC(=O)OC1C=CC2C3CC4=C5C2(C1OC5=C(C=C4)OC(=O)C)CCN3C"),
        RT = c(10.5, 12.1),
        CAS = c("50-36-2", "561-27-3"),
        stringsAsFactors = FALSE
    )
    write.csv(df, "NarcoticsDataset.csv", row.names = FALSE)
}

# 2. Prepare raw_spectra.mzML
mzml_files <- list.files(system.file("spectra", package="RMassBankData"), pattern = "\\.mzML$", full.names = TRUE)
if (length(mzml_files) > 0) {
    file.copy(mzml_files[1], "raw_spectra.mzML", overwrite = TRUE)
} else {
    # Fallback dummy mzML if no files are found
    writeLines('<?xml version="1.0" encoding="utf-8"?><mzML xmlns="http://psi.hupo.org/ms/mzml" version="1.1.0"></mzML>', "raw_spectra.mzML")
}