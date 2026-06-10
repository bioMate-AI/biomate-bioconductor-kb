library("OTUbase")

dirPath <- system.file("extdata/Sogin_2006", package="OTUbase")

files_to_copy <- c(
    "sogin.groups",
    "sogin.unique.filter.fn.list",
    "sample_metadata.txt",
    "sogin.fasta"
)

for (f in files_to_copy) {
    src <- file.path(dirPath, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        stop(paste("Required file not found in package extdata:", src))
    }
}