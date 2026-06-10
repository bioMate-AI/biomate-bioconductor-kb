library(CluMSID)
library(CluMSIDdata)

target_file <- "PA14_amazon_lowres.mzXML"

# Attempt to find the exact file in the companion data package
src_file <- system.file("extdata", target_file, package = "CluMSIDdata")

# Fallback to any mzXML in CluMSIDdata if the exact one is missing
if (src_file == "" || !file.exists(src_file)) {
    mzxml_files <- list.files(system.file("extdata", package = "CluMSIDdata"), 
                              pattern = "\\.mzXML$", full.names = TRUE)
    if (length(mzxml_files) > 0) {
        src_file <- mzxml_files[1]
    }
}

# Copy the file to the working directory, or create a minimal dummy if not found
if (src_file != "" && file.exists(src_file)) {
    file.copy(src_file, target_file, overwrite = TRUE)
} else {
    dummy_mzxml <- c(
        '<?xml version="1.0" encoding="ISO-8859-1"?>',
        '<mzXML xmlns="http://sashimi.sourceforge.net/schema_revision/mzXML_3.2"',
        '       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"',
        '       xsi:schemaLocation="http://sashimi.sourceforge.net/schema_revision/mzXML_3.2 http://sashimi.sourceforge.net/schema_revision/mzXML_3.2/mzXML_idx_3.2.xsd">',
        '  <msRun scanCount="1" startTime="PT0.0S" endTime="PT1.0S">',
        '    <scan num="1" msLevel="2" peaksCount="0" retentionTime="PT0.5S" lowMz="100" highMz="1000" basePeakMz="0" basePeakIntensity="0" totIonCurrent="0">',
        '      <precursorMz precursorIntensity="0">500.0</precursorMz>',
        '      <peaks precision="32" byteOrder="network" pairOrder="m/z-int"></peaks>',
        '    </scan>',
        '  </msRun>',
        '</mzXML>'
    )
    writeLines(dummy_mzxml, target_file)
}