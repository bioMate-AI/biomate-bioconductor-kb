library(AlphaBeta)
library(data.table)

# Locate the directories containing the example data shipped with the package
soma_dir <- system.file("extdata/soma", package="AlphaBeta")
vg_dir <- system.file("extdata/vg", package="AlphaBeta")
dm_dir <- system.file("extdata/dm", package="AlphaBeta")

# Copy SOMA_nodelist2.fn and SOMA_edgelist2.fn to the working directory
file.copy(file.path(soma_dir, "SOMA_nodelist2.fn"), "SOMA_nodelist2.fn", overwrite = TRUE)
file.copy(file.path(soma_dir, "SOMA_edgelist2.fn"), "SOMA_edgelist2.fn", overwrite = TRUE)

# Copy all potential methylome files to the working directory
# The nodelist files contain references to these methylome files, and the workflow
# expects to find them or copy them to the current working directory.
if (nzchar(soma_dir)) {
  soma_files <- list.files(soma_dir, full.names = TRUE)
  file.copy(soma_files, ".", overwrite = TRUE)
}

if (nzchar(vg_dir)) {
  vg_files <- list.files(vg_dir, full.names = TRUE)
  file.copy(vg_files, ".", overwrite = TRUE)
}

if (nzchar(dm_dir)) {
  dm_files <- list.files(dm_dir, full.names = TRUE)
  file.copy(dm_files, ".", overwrite = TRUE)
}

# Verify the required files exist
stopifnot(file.exists("SOMA_nodelist2.fn"))
stopifnot(file.exists("SOMA_edgelist2.fn"))