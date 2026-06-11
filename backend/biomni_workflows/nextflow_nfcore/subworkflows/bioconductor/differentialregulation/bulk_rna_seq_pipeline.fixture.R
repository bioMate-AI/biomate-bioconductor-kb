library(DifferentialRegulation)

# Search for existing bulk RNA-seq example files in the package
data_dir <- system.file("extdata", package = "DifferentialRegulation")
quant_files <- list.files(data_dir, pattern = "quant.sf", recursive = TRUE, full.names = TRUE)
eq_files <- list.files(data_dir, pattern = "eq_classes.txt", recursive = TRUE, full.names = TRUE)

# 1. Generate or copy quant.sf
if (length(quant_files) > 0) {
  file.copy(quant_files[1], "quant.sf", overwrite = TRUE)
} else {
  # Construct a synthetic Salmon quant.sf file
  quant_sf <- data.frame(
    Name = c("tx1-S", "tx1-U", "tx2-S", "tx2-U"),
    Length = c(1000, 2000, 1500, 2500),
    EffectiveLength = c(950, 1950, 1450, 2450),
    TPM = c(10, 5, 20, 2),
    NumReads = c(100, 50, 200, 20)
  )
  write.table(quant_sf, "quant.sf", sep = "\t", quote = FALSE, row.names = FALSE)
}

# 2. Generate or copy eq_classes.txt.gz
if (length(eq_files) > 0) {
  if (grepl("\\.gz$", eq_files[1])) {
    file.copy(eq_files[1], "eq_classes.txt.gz", overwrite = TRUE)
  } else {
    gz <- gzfile("eq_classes.txt.gz", "w")
    writeLines(readLines(eq_files[1]), gz)
    close(gz)
  }
} else {
  # Construct a synthetic Salmon eq_classes.txt file (v0.14+ format)
  eq_lines <- c(
    "1",
    "3.1.0",
    "4",
    "3",
    "tx1-S",
    "tx1-U",
    "tx2-S",
    "tx2-U",
    "1 0 100",
    "1 1 50",
    "2 0 1 10"
  )
  gz <- gzfile("eq_classes.txt.gz", "w")
  writeLines(eq_lines, gz)
  close(gz)
}