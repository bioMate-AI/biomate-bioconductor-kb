library(lipidr)

datadir <- system.file("extdata", package = "lipidr")

# Locate and copy the data.csv file(s)
data_files <- list.files(datadir, pattern = "data\\.csv$", full.names = TRUE)
if (length(data_files) > 0) {
    # Copy the first matching file to exactly "data.csv"
    file.copy(data_files[1], "data.csv", overwrite = TRUE)
} else {
    # Fallback synthetic data if not found in extdata
    df <- data.frame(
        `Replicate Name` = c("S1A", "S2A"),
        `Precursor Mz` = c(692.5, 690.5),
        `Precursor Charge` = c(1, 1),
        `Product Mz` = c(551.5, 549.5),
        `Product Charge` = c(1, 1),
        `Molecule Name` = c("PE 32:0", "PE 32:1"),
        Area = c(1000, 2000),
        `Retention Time` = c(5.5, 5.6),
        Background = c(10, 20),
        check.names = FALSE
    )
    write.csv(df, "data.csv", row.names = FALSE)
}

# Locate and copy the clin.csv file
clin_file <- list.files(datadir, pattern = "clin\\.csv$", full.names = TRUE)
if (length(clin_file) > 0) {
    file.copy(clin_file[1], "clin.csv", overwrite = TRUE)
} else {
    # Fallback synthetic clinical data if not found in extdata
    clin_df <- data.frame(
        sample = c("S1A", "S2A"),
        group = c("NormalDiet_water", "NormalDiet_water"),
        Diet = c("Normal", "Normal"),
        BileAcid = c("water", "water")
    )
    write.csv(clin_df, "clin.csv", row.names = FALSE)
}