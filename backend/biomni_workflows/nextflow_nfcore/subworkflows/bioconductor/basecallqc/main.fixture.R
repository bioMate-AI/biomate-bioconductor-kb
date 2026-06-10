library(basecallQC)

extdata_dir <- system.file("extdata", package="basecallQC")

# Find and copy config.ini
config_files <- list.files(extdata_dir, pattern="config.ini", recursive=TRUE, full.names=TRUE)
if (length(config_files) > 0) {
    file.copy(config_files[1], "config.ini", overwrite = TRUE)
} else {
    writeLines(c("[Run]", "RunId=12345"), "config.ini")
}

# Find and copy runParameters.xml
runXML_files <- list.files(extdata_dir, pattern="runParameters.xml", recursive=TRUE, full.names=TRUE)
if (length(runXML_files) > 0) {
    file.copy(runXML_files[1], "runParameters.xml", overwrite = TRUE)
} else {
    writeLines(c("<?xml version=\"1.0\"?>", "<RunParameters>", "</RunParameters>"), "runParameters.xml")
}

# Find and copy SampleSheet.csv
sampleSheet_files <- list.files(extdata_dir, pattern="\\.csv$", recursive=TRUE, full.names=TRUE)
if (length(sampleSheet_files) > 0) {
    file.copy(sampleSheet_files[1], "SampleSheet.csv", overwrite = TRUE)
} else {
    writeLines(c("[Data]", "Sample_Project,Lane,Sample_ID,Sample_Name,Index,Index2", "EMP,1,A,1,CGATGT,"), "SampleSheet.csv")
}