library(ngsReports)

# Find the fastqc.zip files shipped with ngsReports
fileDir <- system.file("extdata", package = "ngsReports")
files <- list.files(fileDir, pattern = "fastqc.zip$", full.names = TRUE)

if (length(files) > 0) {
    # Copy the first fastqc.zip to the working directory as expected by the workflow
    file.copy(files[1], "fastqc.zip", overwrite = TRUE)
    
    # Extract it to fastqc_extracted_dir as expected by the workflow
    dir.create("fastqc_extracted_dir", showWarnings = FALSE)
    unzip(files[1], exdir = "fastqc_extracted_dir")
} else {
    stop("No fastqc.zip files found in ngsReports extdata")
}