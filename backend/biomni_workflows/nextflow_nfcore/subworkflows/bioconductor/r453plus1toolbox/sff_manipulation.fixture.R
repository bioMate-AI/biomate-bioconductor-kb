library(R453Plus1Toolbox)

# Locate the example.sff file shipped with the package
sff_file <- system.file("extdata", "SFF", "example.sff", package="R453Plus1Toolbox")

# Fallback search if the exact path has changed
if (!file.exists(sff_file)) {
    sff_file <- list.files(system.file("extdata", package="R453Plus1Toolbox"), 
                           pattern="example\\.sff$", recursive=TRUE, full.names=TRUE)[1]
}

if (length(sff_file) > 0 && !is.na(sff_file) && file.exists(sff_file)) {
    file.copy(sff_file, "example.sff", overwrite = TRUE)
} else {
    stop("Could not find example.sff in R453Plus1Toolbox installation.")
}