library(eisaR)
library(GenomicFeatures)

# The workflow requires the following files in the working directory:
# hg19sub.sqlite, samples_rna_single.txt, hg19sub.fa, rna_reads.fq.bz2
# These are shipped with the eisaR package in the extdata directory.

expected_files <- c(
  "hg19sub.sqlite",
  "samples_rna_single.txt",
  "hg19sub.fa",
  "rna_reads.fq.bz2"
)

for (f in expected_files) {
  # Find the file in the package
  src <- list.files(system.file("extdata", package = "eisaR"), 
                    pattern = paste0("^", f, "$"), 
                    recursive = TRUE, 
                    full.names = TRUE)
  
  if (length(src) > 0 && file.exists(src[1])) {
    file.copy(src[1], f, overwrite = TRUE)
  } else {
    # Fallback to creating minimal synthetic files if not found
    if (f == "hg19sub.sqlite") {
      # Create a minimal TxDb and save as sqlite
      gr <- GRanges("chr1", IRanges(1, 1000), strand="+", type="gene", gene_id="gene1")
      txdb <- makeTxDbFromGRanges(gr)
      saveDb(txdb, file=f)
    } else if (f == "samples_rna_single.txt") {
      df <- data.frame(FileName = "rna_reads.fq.bz2", SampleName = "Sample1")
      write.table(df, file = f, sep = "\t", row.names = FALSE, quote = FALSE)
    } else if (f == "hg19sub.fa") {
      writeLines(c(">chr1", "ACGTACGTACGT"), f)
    } else if (f == "rna_reads.fq.bz2") {
      con <- bzfile(f, "w")
      writeLines(c("@read1", "ACGT", "+", "IIII"), con)
      close(con)
    }
  }
}