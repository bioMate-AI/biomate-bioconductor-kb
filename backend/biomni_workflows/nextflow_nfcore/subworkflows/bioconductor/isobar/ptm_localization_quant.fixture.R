library(isobar)

# Construct synthetic identifications.id.csv matching the exact format expected by readIBSpectra
df_id <- data.frame(
  accession = c("PROT1", "PROT2", "PROT3"),
  peptide = c("SPLSPTETFSWPDVR", "ANOTHERK", "YETANOTHERK"),
  modif = c("PHOS", "", "PHOS"),
  charge = c(2, 3, 2),
  theo.mass = c(1000.5, 1500.5, 1200.5),
  exp.mass = c(1000.5, 1500.5, 1200.5),
  parent.intens = c(10000, 20000, 15000),
  spectrum = c("spectrum_1", "spectrum_2", "spectrum_3"),
  stringsAsFactors = FALSE
)

write.table(df_id, "identifications.id.csv", sep="\t", row.names=FALSE, quote=FALSE)

# Construct synthetic peaklist.mgf matching the spectra in the identifications file
mgf_lines <- c()
for (i in 1:nrow(df_id)) {
  mgf_lines <- c(mgf_lines, "BEGIN IONS")
  mgf_lines