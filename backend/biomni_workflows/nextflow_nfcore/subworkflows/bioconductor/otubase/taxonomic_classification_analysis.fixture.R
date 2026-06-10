library("OTUbase")

dirPath <- system.file("extdata/Sogin_2006", package="OTUbase")

files_to_copy <- c(
  "sogin.fasta",
  "sample_metadata.txt",
  "sogin.unique.fix.tax",
  "sogin.names",
  "sogin.groups"
)

for (f in files_to_copy) {
  src <- file.path(dirPath, f)
  if (file.exists(src)) {
    file.copy(src, f, overwrite = TRUE)
  } else {
    alt_src <- list.files(system.file("extdata", package="OTUbase"), pattern=f, recursive=TRUE, full.names=TRUE)
    if (length(alt_src) > 0) {
      file.copy(alt_src[1], f, overwrite = TRUE)
    } else {
      stop(paste("File not found in package:", f))
    }
  }
}