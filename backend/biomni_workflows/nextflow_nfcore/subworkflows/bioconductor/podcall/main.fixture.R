library(PoDCall)

# 1. Sample_names.csv
sample_sheet_path <- system.file("extdata", "Sample_names.csv", package="PoDCall")
if (file.exists(sample_sheet_path)) {
    file.copy(sample_sheet_path, "Sample_names.csv", overwrite = TRUE)
} else {
    sample_sheet <- data.frame(
        Well = c("A04", "B04", "D04"),
        Sample = c("SW1463", "SW403", "SW480"),
        TargetType = rep("Ch1Unknown", 3),
        Target = rep("VIM", 3)
    )
    write.csv(sample_sheet, "Sample_names.csv", row.names = FALSE)
}

# 2. amplitude_files.csv and actual amplitude files ending with _wellID_amplitude.csv
amp_dir <- system.file("extdata", "Amplitudes", package="PoDCall")
if (dir.exists(amp_dir)) {
    amp_files <- list.files(amp_dir, pattern = "\\.csv$", full.names = TRUE)
    file.copy(amp_files, ".", overwrite = TRUE)
    
    # Ensure the exact requested filename 'amplitude_files.csv' is also present
    if (length(amp_files) > 0) {
        file.copy(amp_files[1], "amplitude_files.csv", overwrite = TRUE)
    }
} else {
    amp_data <- data.frame(
        `Ch1 Amplitude` = runif(100, 500, 2000),
        `Ch2 Amplitude` = runif(100, 500, 2000),
        check.names = FALSE
    )
    write.csv(amp_data, "test_A04_amplitude.csv", row.names = FALSE)
    write.csv(amp_data, "amplitude_files.csv", row.names = FALSE)
}