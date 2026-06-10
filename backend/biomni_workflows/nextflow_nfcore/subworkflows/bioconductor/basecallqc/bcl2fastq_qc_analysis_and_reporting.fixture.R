library(basecallQC)

extdata_dir <- system.file("extdata", package="basecallQC")
all_files <- list.files(extdata_dir, recursive = TRUE, full.names = TRUE)

# runParameters.xml
run_xml <- grep("runParameters\\.xml$", all_files, value = TRUE)[1]
if (!is.na(run_xml)) {
    file.copy(run_xml, "runParameters.xml", overwrite = TRUE)
} else {
    writeLines("<RunParameters></RunParameters>", "runParameters.xml")
}

# config.ini
config_ini <- grep("config\\.ini$", all_files, value = TRUE)[1]
if (!is.na(config_ini)) {
    file.copy(config_ini, "config.ini", overwrite = TRUE)
} else {
    writeLines("[Config]", "config.ini")
}

# SampleSheet.csv
sample_sheet <- grep("SampleSheet\\.csv$", all_files, ignore.case = TRUE, value = TRUE)[1]
if (is.na(sample_sheet)) {
    sample_sheet <- grep("\\.csv$", all_files, value = TRUE)[1]
}
if (!is.na(sample_sheet)) {
    file.copy(sample_sheet, "SampleSheet.csv", overwrite = TRUE)
} else {
    writeLines("Lane,Sample_ID,Sample_Name,Sample_Project,Index,Index2\n1,A,A,EMP,CGATGT,", "SampleSheet.csv")
}

# ConversionStats.xml
conv_stats <- grep("ConversionStats\\.xml$", all_files, value = TRUE)[1]
if (!is.na(conv_stats)) {
    file.copy(conv_stats, "ConversionStats.xml", overwrite = TRUE)
} else {
    writeLines("<Stats></Stats>", "ConversionStats.xml")
}

# DemultiplexingStats.xml
demux_stats <- grep("DemultiplexingStats\\.xml$", all_files, value = TRUE)[1]
if (!is.na(demux_stats)) {
    file.copy(demux_stats, "DemultiplexingStats.xml", overwrite = TRUE)
} else {
    writeLines("<Stats></Stats>", "DemultiplexingStats.xml")
}