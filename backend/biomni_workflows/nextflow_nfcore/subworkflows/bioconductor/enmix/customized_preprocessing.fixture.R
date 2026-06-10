library(ENmix)
library(minfiData)

input_dir <- "directory path for idat files"
dir.create(input_dir, showWarnings = FALSE, recursive = TRUE)

minfi_extdata <- file.path(find.package("minfiData"), "extdata")
files_to_copy <- list.files(minfi_extdata, recursive = TRUE, full.names = TRUE)

for (f in files_to_copy) {
    rel_path <- sub(paste0("^", minfi_extdata, "/"), "", f)
    dest_path <- file.path(input_dir, rel_path)
    dir.create(dirname(dest_path), showWarnings = FALSE, recursive = TRUE)
    file.copy(f, dest_path)
}