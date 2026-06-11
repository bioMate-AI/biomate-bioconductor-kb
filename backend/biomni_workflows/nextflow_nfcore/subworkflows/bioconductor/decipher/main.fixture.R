library(DECIPHER)
library(Biostrings)

seqs <- DNAStringSet(c(
  "Root;Bacteria;Firmicutes;Bacilli;Bacillales;Bacillaceae;Bacillus" = "ATGCGTACGTTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC",
  "Root;Bacteria;Proteobacteria;Gammaproteobacteria;Enterobacteriales;Enterobacteriaceae;Escherichia" = "ATGCGCACGTTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC"
))
writeXStringSet(seqs, "seqs_path")

taxid_lines <- c(
  "0*Root*-1*0*rootrank",
  "1*Bacteria*0*1*domain",
  "2*Firmicutes*1*2*phylum",
  "3*Bacilli*2*3*class",
  "4*Bacillales*3*4*order",
  "5*Bacillaceae*4*5*family",
  "6*Bacillus*5*6*genus",
  "7*Proteobacteria*1*2*phylum",
  "8*Gammaproteobacteria*7*3*class",
  "9*Enterobacteriales*8*4*order",
  "10*Enterobacteriaceae*9*5*family",
  "11*Escherichia*10*6*genus"
)
writeLines(taxid_lines, "rank_path")

fas_file <- system.file("extdata", "Bacteria_175seqs.fas", package="DECIPHER")
file.copy(fas_file, "fas")