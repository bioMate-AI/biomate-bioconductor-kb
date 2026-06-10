library(PSMatch)

# Attempt to locate shipped example files from msdata or PSMatch
mzml_src <- NA
mzid_src <- NA

if (requireNamespace("msdata", quietly = TRUE)) {
    mzml_src <- system.file("mzid", "TMT_Erwinia_1uLSike_Top10HCD_isol2_45stepped_60min_01-20141210.mzML.gz", package = "msdata")
    mzid_src <- system.file("mzid", "TMT_Erwinia_1uLSike_Top10HCD_isol2_45stepped_60min_01-20141210.mzid", package = "msdata")
}

# Fallback to searching within PSMatch or msdata
if (is.na(mzml_src) || !file.exists(mzml_src)) {
    mzml_src <- list.files(system.file(package = "PSMatch"), pattern = "\\.mzML\\.gz$", recursive = TRUE, full.names = TRUE)[1]
    if (is.na(mzml_src)) {
        mzml_src <- list.files(system.file(package = "msdata"), pattern = "\\.mzML\\.gz$", recursive = TRUE, full.names = TRUE)[1]
    }
}

if (is.na(mzid_src) || !file.exists(mzid_src)) {
    mzid_src <- list.files(system.file(package = "PSMatch"), pattern = "\\.mzid$", recursive = TRUE, full.names = TRUE)[1]
    if (is.na(mzid_src)) {
        mzid_src <- list.files(system.file(package = "msdata"), pattern = "\\.mzid$", recursive = TRUE, full.names = TRUE)[1]
    }
}

# Copy or create file.mzML.gz
if (!is.na(mzml_src) && file.exists(mzml_src)) {
    file.copy(mzml_src, "file.mzML.gz", overwrite = TRUE)
} else {
    gz <- gzfile("file.mzML.gz", "w")
    writeLines(c('<?xml version="1.0" encoding="utf-8"?>', 
                 '<mzML xmlns="http://psi.hupo.org/ms/mzml" version="1.1.0">', 
                 '</mzML>'), gz)
    close(gz)
}

# Copy or create file.mzid
if (!is.na(mzid_src) && file.exists(mzid_src)) {
    file.copy(mzid_src, "file.mzid", overwrite = TRUE)
} else {
    writeLines(c('<?xml version="1.0" encoding="UTF-8"?>', 
                 '<MzIdentML id="123" version="1.1.0" xmlns="http://psidev.info/psi/pi/mzIdentML/1.1">', 
                 '</MzIdentML>'), "file.mzid")
}