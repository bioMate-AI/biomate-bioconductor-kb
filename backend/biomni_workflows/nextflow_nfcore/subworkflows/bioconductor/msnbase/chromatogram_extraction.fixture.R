library(MSnbase)

mzml_candidates <- list.files(system.file("extdata", package = "MSnbase"), 
                              pattern = "srm_data\\.mzML$", 
                              recursive = TRUE, 
                              full.names = TRUE)

if (length(mzml_candidates) > 0) {
    file.copy(mzml_candidates[1], "srm_data.mzML", overwrite = TRUE)
} else {
    stop("Could not find srm_data.mzML in MSnbase extdata.")
}