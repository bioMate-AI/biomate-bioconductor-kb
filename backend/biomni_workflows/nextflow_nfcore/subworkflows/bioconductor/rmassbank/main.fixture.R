library(RMassBank)
library(RMassBankData)

# 1. mysettings.ini
# RMassBank settings are typically YAML files (often with an .ini extension).
# We search for an existing valid settings file in the installed packages.
ini_files <- c(
    list.files(system.file(package="RMassBankData"), pattern="\\.ini$", full.names=TRUE, recursive=TRUE),
    list.files(system.file(package="RMassBank"), pattern="\\.ini$", full.names=TRUE, recursive=TRUE)
)

if (length(ini_files) > 0) {
    file.copy(ini_files[1], "mysettings.ini", overwrite = TRUE)
} else {
    # Fallback: Create a minimal settings file that loadRmbSettings can parse
    settings_list <- list(
        deprofile = "NA",
        rtMargin = 0.4,
        rtShift = -0.3,
        babeldir = "NA",
        use_version = 2,
        use_epaw = 1,
        recalibrateBy = "dppm",
        recalibrateMS1 = "common",
        recalibrator = list(MS1="recalibrate.loess", MS2="recalibrate.loess"),
        multiplicityFilter = 1,
        spectraList = list(
            list(mode="CID", ces="35%", ce="35 % (nominal)", res=7500)
        )
    )
    if (requireNamespace("yaml", quietly = TRUE)) {
        yaml::write_yaml(settings_list, "mysettings.ini")
    } else {
        cat("deprofile: NA\nrtMargin: 0.4\nrtShift: -0.3\nbabeldir: NA\nuse_version: 2\nuse_epaw: 1\nrecalibrateBy: dppm\nrecalibrateMS1: common\nrecalibrator:\n  MS1: recalibrate.loess\n  MS2: recalibrate.loess\nmultiplicityFilter: 1\n", file="mysettings.ini")
    }
}

# 2. Compoundlist.csv
# The vignette uses NarcoticsDataset.csv from RMassBankData
csv_file <- system.file("list/NarcoticsDataset.csv", package="RMassBankData")
if (file.exists(csv_file)) {
    file.copy(csv_file, "Compoundlist.csv", overwrite = TRUE)
} else {
    # Fallback synthetic compound list matching the required columns
    df <- data.frame(
        ID = c(1, 2),
        Name = c("CompoundA", "CompoundB"),
        SMILES = c("CC", "CCO"),
        RT = c(1.5, 2.0),
        CAS = c("123-45-6", "654-32-1")
    )
    write.csv(df, "Compoundlist.csv", row.names = FALSE)
}

# 3. raw_spectra.mzML
# The vignette uses mzML files from RMassBankData
mzml_files <- list.files(system.file("spectra", package="RMassBankData"), pattern="\\.mzML$", full.names = TRUE)
if (length(mzml_files) > 0) {
    file.copy(mzml_files[1], "raw_spectra.mzML", overwrite = TRUE)
} else {
    # Fallback empty file
    file.create("raw_spectra.mzML")
}

# 4. pH_narcotics_RF.RData (used in the excerpt)
# The vignette loads this workspace from RMassBankData
rdata_file <- system.file("results/pH_narcotics_RF.RData", package="RMassBankData")
if (file.exists(rdata_file)) {
    file.copy(rdata_file, "pH_narcotics_RF.RData", overwrite = TRUE)
} else {
    # Fallback empty workspace
    storedW <- newMsmsWorkspace()
    save(storedW, file="pH_narcotics_RF.RData")
}