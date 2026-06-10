suppressPackageStartupMessages({
    library(MSnbase)
    library(xcms)
    library(MassSpecWavelet)
})

# 1. Locate a valid MS data file from installed packages to use as a template
search_dirs <- c(
    system.file("extdata", package = "xcms"),
    system.file("cdf", package = "faahKO"),
    system.file("microtofq", package = "msdata"),
    system.file("proteomics", package = "msdata"),
    system.file("extdata", package = "MSnbase")
)

candidate_files <- unlist(lapply(search_dirs, function(d) {
    if (d != "") {
        list.files(d, pattern = "\\.(mzML|cdf|mzXML|mzData)$", 
                   ignore.case = TRUE, full.names = TRUE, recursive = TRUE)
    }
}))

if (length(candidate_files) == 0) {
    stop("No MS data files found in installed packages to use as a template.")
}

src_file <- candidate_files[1]

# 2. Read the template file and subset to 1 spectrum to mimic direct injection MS
# (as described in the vignette: "we have only a single spectrum available for each sample")
raw_data <- suppressWarnings(readMSData(src_file, mode = "inMemory"))
if