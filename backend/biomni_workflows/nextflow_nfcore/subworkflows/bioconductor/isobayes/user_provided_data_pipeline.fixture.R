library(IsoBayes)

# Copy or create the TPM file
tpm_file <- system.file("extdata", "jurkat_isoform_kallisto.tsv", package = "IsoBayes")
if (file.exists(tpm_file)) {
  file.copy(tpm_file, "jurkat_isoform_kallisto.tsv", overwrite = TRUE)
  tpm_data <- read.delim(tpm_file)
  iso1 <- as.character(tpm_data$isoname[1])
  iso2 <- as.character(tpm_data$isoname[2])
} else {
  iso1 <- "iso1"
  iso2 <- "iso2"
  tpm_data <- data.frame(isoname = c(iso1, iso2), tpm = c(10.5, 2.3))
  write.table(tpm_data, "jurkat_isoform_kallisto.tsv", sep = "\t", row.names = FALSE, quote = FALSE)
}

# Create the user-provided PSM data file 'X'
X_data <- data.frame(
  Y = c(10, 20, 5),
  EC = c(iso1, iso2, paste0(iso1, "|", iso2)),
  FDR = c(0.01, 0.05, 0.02),
  PEP = c(0.001, 0.005, 0.002),
  sequence = c("PEPTIDE1", "PEPTIDE2", "PEPTIDE3")
)
write.table(X_data, "X", sep = "\t", row.names = FALSE, quote = FALSE)