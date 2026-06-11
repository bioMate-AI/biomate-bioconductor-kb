library(RMassBank)
library(RMassBankData)

csv_file <- system.file("list/NarcoticsDataset.csv", package="RMassBankData")
if (file.exists(csv_file)) {
    file.copy(csv_file, "NarcoticsDataset.csv", overwrite = TRUE)
} else {
    df <- data.frame(
        ID = c(2818, 2819),
        Name = c("1-Methyl-4-phenylpyridinium", "1-Methyl-4-phenyl-1,2,3,6-tetrahydropyridine"),
        SMILES = c("C[N+]1=CC=C(C=C1)C2=CC=CC=C2", "CN1CC=C(CC1)C2=CC=CC=C2"),
        RT = c(1.5, 2.0),
        CAS = c("36913-39-4", "28289-54-5")
    )
    write.csv(df, "NarcoticsDataset.csv", row.names = FALSE)
}

mzml_files <- list.files(system.file("spectra", package="RMassBankData"), pattern = "\\.mzML$", full.names = TRUE)
if (length(mzml_files) > 0) {
    file.copy(mzml_files, basename(mzml_files), overwrite = TRUE)
} else {
    file.create("dummy.mzML")
}