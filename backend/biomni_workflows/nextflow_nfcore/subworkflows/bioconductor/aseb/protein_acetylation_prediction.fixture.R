library(ASEB)

files_to_copy <- c(
  "background_sites.fa",
  "predefined_sites.fa",
  "proteins_to_test.fa"
)

for (f in files_to_copy) {
  src <- system.file("extdata", f, package = "ASEB")
  if (file.exists(src)) {
    file.copy(src, f, overwrite = TRUE)
  } else {
    # Fallback search in case it's in a sub-directory
    src_search <- list.files(system.file("extdata", package = "ASEB"), pattern = f, recursive = TRUE, full.names = TRUE)
    if (length(src_search) > 0) {
      file.copy(src_search[1], f, overwrite = TRUE)
    } else {
      stop(paste("Required file not found in package:", f))
    }
  }
}