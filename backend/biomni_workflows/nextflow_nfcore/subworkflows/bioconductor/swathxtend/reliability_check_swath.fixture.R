library(SwathXtend)

# Find files shipped with the package
pkg_files <- list.files(system.file(package="SwathXtend"), recursive=TRUE, full.names=TRUE)

# Helper function to copy package files to the working directory
copy_pkg_file <- function(pattern, dest) {
    matches <- grep(pattern, pkg_files, ignore.case=TRUE, value=TRUE)
    if (length(matches) > 0) {
        file.copy(matches[1], dest, overwrite=TRUE)
        return(TRUE)
    }
    return(FALSE)
}

# Attempt to copy the real files from the package
copy_pkg_file("Lib2\\.txt$|seed_library\\.txt$", "seed_library.txt")
copy_pkg_file("Lib3\\.txt$|extended_library\\.txt$", "extended_library.txt")
copy_pkg_file("Swath_result_seed\\.xlsx$|swath_result_seed\\.xlsx$", "swath_result_seed.xlsx")
copy_pkg_file("Swath_result_ext\\.xlsx$|swath_result_ext\\.xlsx$", "swath_result_ext.xlsx")

# Fallback: Create synthetic seed library if not found
if (!file.exists("seed_library.txt")) {
    df_lib <- data.frame(
        Q1 = 500.1, Q3 = 300.1, RT_detected = 45.2, protein_name = "PROT_A",
        isotype = "light", relative_intensity = 100, stripped_sequence = "PEPTIDE",
        modification_sequence = "PEPTIDE", prec_z = 2, frg_type = "y", frg_z = 1,
        frg_nr = 3, iRT = 45.2, uniprot_id = "P12345", decoy = FALSE,
        confidence = 0.99, shared = FALSE, N = 1
    )
    write.table(df_lib, "seed_library.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# Fallback: Create synthetic extended library if not found
if (!file.exists("extended_library.txt")) {
    df_lib_ext <- data.frame(
        Q1 = 500.1, Q3 = 300.1, RT_detected = 45.2, protein_name = "PROT_A",
        isotype = "light", relative_intensity = 100, stripped_sequence = "PEPTIDE",
        modification_sequence = "PEPTIDE", prec_z = 2, frg_type = "y", frg_z = 1,
        frg_nr = 3, iRT = 45.2, uniprot_id = "P12345", decoy = FALSE,
        confidence = 0.99, shared = FALSE, N = 1
    )
    write.table(df_lib_ext, "extended_library.txt", sep="\t", row.names=FALSE, quote=FALSE)
}

# Fallback: Create synthetic SWATH result for seed library if not found
if (!file.exists("swath_result_seed.xlsx")) {
    if (requireNamespace("openxlsx", quietly=TRUE)) {
        wb <- openxlsx::createWorkbook()
        openxlsx::addWorksheet(wb, "FDR")
        openxlsx::writeData(wb, "FDR", data.frame(Peptide="PEPTIDE", nfdr.pass=1, run1=0.01))
        openxlsx::addWorksheet(wb, "Peptide")
        openxlsx::writeData(wb, "Peptide", data.frame(Peptide="PEPTIDE", run1=1000))
        openxlsx::saveWorkbook(wb, "swath_result_seed.xlsx", overwrite=TRUE)
    }
}

# Fallback: Create synthetic SWATH result for extended library if not found
if (!file.exists("swath_result_ext.xlsx")) {
    if (requireNamespace("openxlsx", quietly=TRUE)) {
        wb <- openxlsx::createWorkbook()
        openxlsx::addWorksheet(wb, "FDR")
        openxlsx::writeData(wb, "FDR", data.frame(Peptide="PEPTIDE", nfdr.pass=1, run1=0.01))
        openxlsx::addWorksheet(wb, "Peptide")
        openxlsx::writeData(wb, "Peptide", data.frame(Peptide="PEPTIDE", run1=1000))
        openxlsx::saveWorkbook(wb, "swath_result_ext.xlsx", overwrite=TRUE)
    }
}