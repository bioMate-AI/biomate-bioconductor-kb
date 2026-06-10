library(SwathXtend)

# Locate the example files provided by the package
lib2_file <- system.file("files", "Lib2.txt", package="SwathXtend")
lib3_file <- system.file("files", "Lib3.txt", package="SwathXtend")
hydro_file <- system.file("files", "hydroIndex.txt", package="SwathXtend")

# Fallback to recursive search if not found in the exact "files" directory
if (!file.exists(lib2_file) || lib2_file == "") {
    lib2_file <- list.files(system.file(package="SwathXtend"), pattern="Lib2\\.txt$", recursive=TRUE, full.names=TRUE)[1]
}
if (!file.exists(lib3_file) || lib3_file == "") {
    lib3_file <- list.files(system.file(package="SwathXtend"), pattern="Lib3\\.txt$", recursive=TRUE, full.names=TRUE)[1]
}
if (!file.exists(hydro_file) || hydro_file == "") {
    hydro_file <- list.files(system.file(package="SwathXtend"), pattern="hydroIndex\\.txt$", recursive=TRUE, full.names=TRUE)[1]
}

# Copy or generate seed_library.txt
if (!is.na(lib2_file) && file.exists(lib2_file)) {
    file.copy(lib2_file, "seed_library.txt", overwrite = TRUE)
} else {
    # Synthetic PeakView format library
    seed_df <- data.frame(
        Q1 = 500.1, Q3 = 300.1, RT_detected = 45.2, protein_name = "PROT_A",
        isotype = "light", relative_intensity = 100, stripped_sequence = "PEPTIDE",
        modification_sequence = "PEPTIDE", prec_z = 2, frg_type = "y",
        frg_z = 1, frg_nr = 3, iRT = 45.2, uniprot_id = "P12345",
        decoy = FALSE, confidence = 0.99, shared = FALSE, N = 1
    )
    write.table(seed_df, "seed_library.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# Copy or generate addon_library.txt
if (!is.na(lib3_file) && file.exists(lib3_file)) {
    file.copy(lib3_file, "addon_library.txt", overwrite = TRUE)
} else {
    # Synthetic PeakView format library
    addon_df <- data.frame(
        Q1 = 500.1, Q3 = 300.1, RT_detected = 45.5, protein_name = "PROT_A",
        isotype = "light", relative_intensity = 95, stripped_sequence = "PEPTIDE",
        modification_sequence = "PEPTIDE", prec_z = 2, frg_type = "y",
        frg_z = 1, frg_nr = 3, iRT = 45.5, uniprot_id = "P12345",
        decoy = FALSE, confidence = 0.99, shared = FALSE, N = 1
    )
    write.table(addon_df, "addon_library.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# Copy or generate hydro_index.txt
if (!is.na(hydro_file) && file.exists(hydro_file)) {
    file.copy(hydro_file, "hydro_index.txt", overwrite = TRUE)
} else {
    # Synthetic hydrophobicity index
    hydro_df <- data.frame(
        Sequence = c("PEPTIDE", "ANOTHER"),
        Length = c(7, 7),
        Hydrophobicity = c(15.2, 20.1)
    )
    write.table(hydro_df, "hydro_index.txt", sep="\t", row.names=FALSE, quote=FALSE)
}