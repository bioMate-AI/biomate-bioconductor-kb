library(IsoCorrectoR)

extdata_dir <- system.file("extdata", package = "IsoCorrectoR")

# Find the shipped example files
meas_files <- list.files(extdata_dir, pattern = "measurement.*\\.csv$", full.names = TRUE, ignore.case = TRUE)
elem_files <- list.files(extdata_dir, pattern = "element.*\\.csv$", full.names = TRUE, ignore.case = TRUE)
mol_files <- list.files(extdata_dir, pattern = "molecule.*\\.csv$", full.names = TRUE, ignore.case = TRUE)

# 1. MeasurementFile
if (length(meas_files) > 0) {
    file.copy(meas_files[1], "MeasurementFile.csv", overwrite = TRUE)
} else {
    # Fallback synthetic data if not found
    meas_data <- data.frame(
        Name = c("Metabolite1", "Metabolite1"),
        Isotopologue = c(0, 1),
        Sample1 = c(1000, 100)
    )
    write.csv(meas_data, "MeasurementFile.csv", row.names = FALSE)
}

# 2. ElementFile
if (length(elem_files) > 0) {
    file.copy(elem_files[1], "ElementFile.csv", overwrite = TRUE)
} else {
    # Fallback synthetic data if not found
    elem_data <- data.frame(
        Element = c("C", "H", "N", "O", "P", "S"),
        Mass = c(12, 1.007825, 14.003074, 15.994915, 30.973762, 31.972071),
        Abundance = c(0.9893, 0.999885, 0.99636, 0.99757, 1, 0.9493),
        Isotope = c("13C", "2H", "15N", "18O", NA, "34S"),
        IsotopeMass = c(13.003355, 2.014102, 15.000109, 17.999161, NA, 33.967867),
        IsotopeAbundance = c(0.0107, 0.000115, 0.00364, 0.00205, NA, 0.0429)
    )
    write.csv(elem_data, "ElementFile.csv", row.names = FALSE)
}

# 3. MoleculeFile
if (length(mol_files) > 0) {
    file.copy(mol_files[1], "MoleculeFile.csv", overwrite = TRUE)
} else {
    # Fallback synthetic data if not found
    mol_data <- data.frame(
        Molecule = c("Metabolite1"),
        Formula = c("C6H12O6"),
        Tracer = c("13C"),
        TracerPurity = c(0.99)
    )
    write.csv(mol_data, "MoleculeFile.csv", row.names = FALSE)
}