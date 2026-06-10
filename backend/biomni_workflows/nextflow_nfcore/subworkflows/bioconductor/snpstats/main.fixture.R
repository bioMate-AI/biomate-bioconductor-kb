library(snpStats)

files_to_copy <- c(
    "sample.ped.gz",
    "sample.info",
    "sample.bed",
    "sample.bim",
    "sample.fam",
    "sample-long.gz",
    "sample-long-alleles.gz"
)

for (f in files_to_copy) {
    src <- system.file("extdata", f, package="snpStats")
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    } else {
        stop(paste("Source file not found in snpStats extdata:", f))
    }
}