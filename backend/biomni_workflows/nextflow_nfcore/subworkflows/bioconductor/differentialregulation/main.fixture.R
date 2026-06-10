library(DifferentialRegulation)

data_dir <- system.file("extdata", package = "DifferentialRegulation")
sample_dir <- file.path(data_dir, "alevin-fry", "organoid1", "alevin")

# Fallback in case the directory structure differs slightly
if (!dir.exists(sample_dir)) {
  all_dirs <- list.dirs(data_dir, recursive = TRUE)
  alevin_dirs <- all_dirs[grep("alevin$", all_dirs)]
  if (length(alevin_dirs) > 0) {
    sample_dir <- alevin_dirs[1]
  }
}

# Copy the alevin-fry output files to the working directory
file.copy(file.path(sample_dir, "quants_mat.mtx"), "quants_mat.mtx", overwrite = TRUE)
file.copy(file.path(sample_dir, "quants_mat_rows.txt"), "quants_mat_rows.txt", overwrite = TRUE)
file.copy(file.path(sample_dir, "quants_mat_cols.txt"), "quants_mat_cols.txt", overwrite = TRUE)
file.copy(file.path(sample_dir, "geqc_counts.mtx"), "geqc_counts.mtx", overwrite = TRUE)
file.copy(file.path(sample_dir, "gene_eqclass.txt.gz"), "gene_eqclass.txt.gz", overwrite = TRUE)

# Copy the cell types assignment file
df_src <- file.path(data_dir, "DF_cell_types.txt")
if (file.exists(df_src)) {
  file.copy(df_src, "DF_cell_types.txt", overwrite = TRUE)
} else {
  # Fallback synthetic creation if missing
  df <- data.frame(cell_id = "dummy_cell", cell_type = "dummy_type")
  write.table(df, "DF_cell_types.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}