library(basecallQC)

extdata_dir <- system.file("extdata", package="basecallQC")

# 1. runParameters.xml
run_xml <- list.files(extdata_dir, pattern="runParameters.xml", recursive=TRUE, full.names=TRUE)[1]
if (!is.na(run_xml) && file.exists(run_xml)) {
    file.copy(run_xml, "runParameters.xml", overwrite=TRUE)
} else {
    writeLines("<RunParameters></RunParameters>", "runParameters.xml")
}

# 2. config.ini
config_ini <- list.files(extdata_dir, pattern="config.ini", recursive=TRUE, full.names=TRUE)[1]
if (!is.na(config_ini) && file.exists(config_ini)) {
    file.copy(config_ini, "config.ini", overwrite=TRUE)
} else {
    writeLines("[Run]\n", "config.ini")
}

# 3. SampleSheet.csv
sample_sheet <- list.files(extdata_dir, pattern="SampleSheet.*\\.csv", ignore.case=TRUE, recursive=TRUE, full.names=TRUE)[1]
if (is.na(sample_sheet)) {
    sample_sheet <- list.files(extdata_dir, pattern="\\.csv$", recursive=TRUE, full.names=TRUE)[1]
}
if (!is.na(sample_sheet) && file.exists(sample_sheet)) {
    file.copy(sample_sheet, "SampleSheet.csv", overwrite=TRUE)
} else {
    writeLines("Lane,Sample_ID,Sample_Name,Sample_Project,Index,Index2\n1,A,A,EMP,CGATGT,", "SampleSheet.csv")
}

# 4. ConversionStats.xml
conv_stats <- list.files(extdata_dir, pattern="ConversionStats.xml", recursive=TRUE, full.names=TRUE)[1]
if (!is.na(conv_stats) && file.exists(conv_stats)) {
    file.copy(conv_stats, "ConversionStats.xml", overwrite=TRUE)
} else {
    writeLines("<?xml version=\"1.0\" encoding=\"utf-8\"?><Stats><Flowcell flowcell-id=\"A\"><Project name=\"all\"><Sample name=\"all\"><Barcode name=\"all\"><Lane number=\"1\"><Tile number=\"1101\"><Raw><ClusterCount>1</ClusterCount><Read number=\"1\"><Yield>1</Yield><YieldQ30>1</YieldQ30><QualityScoreSum>1</QualityScoreSum></Read></Raw></Tile></Lane></Barcode></Sample></Project></Flowcell></Stats>", "ConversionStats.xml")
}

# 5. DemultiplexingStats.xml
demux_stats <- list.files(extdata_dir, pattern="DemultiplexingStats.xml", recursive=TRUE, full.names=TRUE)[1]
if (!is.na(demux_stats) && file.exists(demux_stats)) {
    file.copy(demux_stats, "DemultiplexingStats.xml", overwrite=TRUE)
} else {
    writeLines("<?xml version=\"1.0\" encoding=\"utf-8\"?><Stats><Flowcell flowcell-id=\"A\"><Project name=\"all\"><Sample name=\"all\"><Barcode name=\"all\"><Lane number=\"1\"><BarcodeCount>1</BarcodeCount><PerfectBarcodeCount>1</PerfectBarcodeCount></Lane></Barcode></Sample></Project></Flowcell></Stats>", "DemultiplexingStats.xml")
}