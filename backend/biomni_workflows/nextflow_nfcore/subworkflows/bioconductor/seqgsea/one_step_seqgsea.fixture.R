library(SeqGSEA)

# Create data.dir and copy case/control files
dir.create("data.dir", showWarnings = FALSE)
extdata_dir <- system.file("extdata", package="SeqGSEA", mustWork=TRUE)
case_files <- list.files(extdata_dir, pattern="^SC", full.names=TRUE)
ctrl_files <- list.files(extdata_dir, pattern="^SN", full.names=TRUE)
file.copy(case_files, "data.dir/")
file.copy(ctrl_files, "data.dir/")

# Copy geneset file
gs_file <- system.file("extdata", "gs_symb.txt", package="SeqGSEA", mustWork=TRUE)
file.copy(gs_file, "geneset.file")