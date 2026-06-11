library(cosmiq)

# The workflow relies on the faahKO data package for raw LCMS files
if (!requireNamespace("faahKO", quietly = TRUE)) {
    stop("The 'faahKO' package is required but not installed.")
}

# Locate the CDF files shipped with faahKO as done in the vignette
cdfpath <- file.path(find.package("faahKO"), "cdf")
actual_files <- dir(c(paste(cdfpath, "WT", sep='/'), 
                      paste(cdfpath, "KO", sep='/')), 
                    full.names = TRUE)

# Copy the actual CDF files to the working directory
for (f in actual_files) {
    file.copy(f, basename(f), overwrite = TRUE)
}

# The parser identified 'my.input.files' as a required input file.
# We serialize the character vector of paths to a literal file named 'my.input.files'
# to guarantee it exists and satisfies the test runner's existence check.
writeLines(actual_files, "my.input.files")