library(MSnbase)

# Find and copy an existing mzXML file from the MSnbase package
mzxml_candidates <- list.files(system.file("extdata", package = "MSnbase"), 
                               pattern = "\\.mzXML$", 
                               full.names = TRUE, 
                               recursive = TRUE)

if (length(mzxml_candidates) > 0) {
    file.copy(mzxml_candidates[1], "quantFile.mzXML", overwrite = TRUE)
} else {
    # Fallback: create a minimal valid mzXML file if none is found
    writeLines(c(
        '<?xml version="1.0" encoding="ISO-8859-1"?>',
        '<mzXML xmlns="http://sashimi.sourceforge.net/schema_revision/mzXML_3.2">',
        '<msRun scanCount="0" startTime="PT0S" endTime="PT0S">',
        '</msRun>',
        '</mzXML>'
    ), "quantFile.mzXML")
}

# Find and copy an existing mzid file from the MSnbase package
mzid_candidates <- list.files(system.file("extdata", package = "MSnbase"), 
                              pattern = "\\.mzid$", 
                              full.names = TRUE, 
                              recursive = TRUE)

if (length(mzid_candidates) > 0) {
    file.copy(mzid_candidates[1], "identFile.mzid", overwrite = TRUE)
} else {
    # Fallback: create a minimal valid mzid file if none is found
    writeLines(c(
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<MzIdentML id="dummy" version="1.1.0" xmlns="http://psidev.info/psi/pi/mzIdentML/1.1">',
        '<SequenceCollection></SequenceCollection>',
        '<AnalysisCollection></AnalysisCollection>',
        '<AnalysisProtocolCollection></AnalysisProtocolCollection>',
        '<DataCollection></DataCollection>',
        '</MzIdentML>'
    ), "identFile.mzid")
}