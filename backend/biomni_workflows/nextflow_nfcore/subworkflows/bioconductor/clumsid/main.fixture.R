library(CluMSID)
library(CluMSIDdata)

target_file <- "PA14_maxis_DI.mzXML"
source_file <- system.file("extdata", "PA14_maxis_DI.mzXML", package = "CluMSIDdata")

if (!file.exists(source_file) || source_file == "") {
    mzxml_files <- list.files(system.file("extdata", package = "CluMSIDdata"), pattern = "\\.mzXML$", full.names = TRUE)
    if (length(mzxml_files) > 0) {
        source_file <- mzxml_files[1]
    }
}

if (file.exists(source_file) && source_file != "") {
    file.copy(source_file, target_file, overwrite = TRUE)
} else {
    # Fallback: create a minimal dummy mzXML file if not found
    writeLines(c(
        '<?xml version="1.0" encoding="ISO-8859-1"?>',
        '<mzXML xmlns="http://sashimi.sourceforge.net/schema_revision/mzXML_3.2">',
        '  <msRun scanCount="0" startTime="PT0S" endTime="PT0S">',
        '  </msRun>',
        '</mzXML>'
    ), target_file)
}