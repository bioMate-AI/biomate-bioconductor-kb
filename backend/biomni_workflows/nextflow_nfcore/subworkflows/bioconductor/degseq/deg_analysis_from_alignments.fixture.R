library(DEGseq)

files_to_create <- c(
  "kidneyChr21.bed.txt",
  "liverChr21.bed.txt",
  "refFlatChr21.txt"
)

for (f in files_to_create) {
  src <- system.file("extdata", f, package="DEGseq")
  if (src != "" && file.exists(src)) {
    file.copy(src, f, overwrite = TRUE)
  } else {
    # Fallback to synthetic data if the package does not ship the exact file
    if (grepl("bed", f)) {
      df <- data.frame(
        chrom = c("chr21", "chr21", "chr21"),
        chromStart = c(1000, 2000, 3000),
        chromEnd = c(1050, 2050, 3050),
        name = c("read1", "read2", "read3"),
        score = c(0, 0, 0),
        strand = c("+", "-", "+")
      )
      write.table(df, f, sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
    } else if (grepl("refFlat", f)) {
      df <- data.frame(
        geneName = c("geneA", "geneB"),
        name = c("NM_001", "NM_002"),
        chrom = c("chr21", "chr21"),
        strand = c("+", "-"),
        txStart = c(900, 1900),
        txEnd = c(1100, 2100),
        cdsStart = c(950, 1950),
        cdsEnd = c(1050, 2050),
        exonCount = c(1, 1),
        exonStarts = c("900,", "1900,"),
        exonEnds = c("1100,", "2100,")
      )
      write.table(df, f, sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
    }
  }
}