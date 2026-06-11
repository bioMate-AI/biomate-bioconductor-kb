library(syntenet)

# 1. Copy FASTA files from the package's extdata to the working directory
fasta_dir <- system.file("extdata", "sequences", package = "syntenet")
if (nzchar(fasta_dir)) {
  fasta_files <- list.files(fasta_dir, full.names = TRUE)
  file.copy(fasta_files, ".", overwrite = TRUE)
}

# 2. Copy GFF/GTF files from the package's extdata to the working directory
gff_dir <- system.file("extdata", "annotation", package = "syntenet")
if (nzchar(gff_dir)) {
  gff_files <- list.files(gff_dir, full.names = TRUE)
  file.copy(gff_files, ".", overwrite = TRUE)
}

# 3. Create synthetic DIAMOND/BLAST tabular output files (outfmt 6 format)
# Scerevisiae_Scerevisiae.tsv
sc_sc <- data.frame(
  qseqid = c("YAL001C", "YAL002W"),
  sseqid = c("YAL001C", "YAL002W"),
  pident = c(100, 100),
  length = c(100, 100),
  mismatch = c(0, 0),
  gapopen = c(0, 0),
  qstart = c(1, 1),
  qend = c(100, 100),
  sstart = c(1, 1),
  send = c(100, 100),
  evalue = c(0, 0),
  bitscore = c(200, 200)
)
write.table(sc_sc, "Scerevisiae_Scerevisiae.tsv", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# Olucimarinus_OspRCC809.tsv
ol_os <- data.frame(
  qseqid = c("OL01G00010", "OL01G00020"),
  sseqid = c("ORCC809_01G00010", "ORCC809_01G00020"),
  pident = c(80, 85),
  length = c(100, 100),
  mismatch = c(20, 15),
  gapopen = c(0, 0),
  qstart = c(1, 1),
  qend = c(100, 100),
  sstart = c(1, 1),
  send = c(100, 100),
  evalue = c(1e-10, 1e-15),
  bitscore = c(150, 160)
)
write.table(ol_os, "Olucimarinus_OspRCC809.tsv", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# OspRCC809_Olucimarinus.tsv
os_ol <- data.frame(
  qseqid = c("ORCC809_01G00010", "ORCC809_01G00020"),
  sseqid = c("OL01G00010", "OL01G00020"),
  pident = c(80, 85),
  length = c(100, 100),
  mismatch = c(20, 15),
  gapopen = c(0, 0),
  qstart = c(1, 1),
  qend = c(100, 100),
  sstart = c(1, 1),
  send = c(100, 100),
  evalue = c(1e-10, 1e-15),
  bitscore = c(150, 160)
)
write.table(os_ol, "OspRCC809_Olucimarinus.tsv", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)