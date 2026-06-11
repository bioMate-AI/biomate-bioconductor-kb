library(MSnbase)

# 1. Find and copy the mzXML file
mzxml_candidates <- list.files(system.file("extdata", package = "MSnbase"), 
                               pattern = "\\.mzXML$", 
                               recursive = TRUE, 
                               full.names = TRUE)

if (length(mzxml_candidates) > 0) {
    file.copy(mzxml_candidates[1], "quantFile.mzXML", overwrite = TRUE)
} else {
    # Fallback to msdata package if available
    if (requireNamespace("msdata", quietly = TRUE)) {
        mzxml_candidates <- list.files(system.file("microtofq", package = "msdata"), 
                                       pattern = "\\.mzXML$", 
                                       recursive = TRUE, 
                                       full.names = TRUE)
        if (length(mzxml_candidates) > 0) {
            file.copy(mzxml_candidates[1], "quantFile.mzXML", overwrite = TRUE)
        } else {
            writeLines("<mzXML></mzXML>", "quantFile.mzXML")
        }
    } else {
        writeLines("<mzXML></mzXML>", "quantFile.mzXML")
    }
}

# 2. Find and copy the mzid file
mzid_candidates <- list.files(system.file("extdata", package = "MSnbase"), 
                              pattern = "\\.mzid$", 
                              recursive = TRUE, 
                              full.names = TRUE)

if (length(mzid_candidates) > 0) {
    file.copy(mzid_candidates[1], "identFile.mzid", overwrite = TRUE)
} else {
    # Fallback to msdata package if available
    if (requireNamespace("msdata", quietly = TRUE)) {
        mzid_candidates <- list.files(system.file("mzid", package = "msdata"), 
                                      pattern = "\\.mzid$", 
                                      recursive = TRUE, 
                                      full.names = TRUE)
        if (length(mzid_candidates) > 0) {
            file.copy(mzid_candidates[1], "identFile.mzid", overwrite = TRUE)
        } else {
            writeLines("<MzIdentML></MzIdentML>", "identFile.mzid")
        }
    } else {
        writeLines("<MzIdentML></MzIdentML>", "identFile.mzid")
    }
}