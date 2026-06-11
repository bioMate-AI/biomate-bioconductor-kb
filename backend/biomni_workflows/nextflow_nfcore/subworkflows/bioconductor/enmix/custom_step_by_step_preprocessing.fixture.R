library(ENmix)
library(minfiData)

# Create the directory for IDAT files
idat_dir <- "directory path for idat files"
dir.create(idat_dir, showWarnings = FALSE, recursive = TRUE)

# Locate the extdata directory in minfiData
extdata_path <- file.path(find.package("minfiData"), "extdata")

# Copy all IDAT files to the target directory
idat_files <- list.files(extdata_path, pattern = "\\.idat$", recursive = TRUE, full.names = TRUE)
for (f in idat_files) {
    file.copy(f, file.path(idat_dir, basename(f)))
}

# Locate the sample sheet CSV and copy it to the target file named "csv"
sheet_files <- list.files(extdata_path, pattern = "csv$", recursive = TRUE, full.names = TRUE)
if (length(sheet_files) > 0) {
    sheet <- read.csv(sheet_files[1], stringsAsFactors = FALSE)
    write.csv(sheet, "csv", row.names = FALSE)
} else {
    # Fallback synthetic sample sheet if not found
    sheet <- data.frame(
        Sample_Name = c("Sample1", "Sample2"),
        Sample_Group = c("Control", "Case"),
        stringsAsFactors = FALSE
    )
    write.csv(sheet, "csv", row.names = FALSE)
}