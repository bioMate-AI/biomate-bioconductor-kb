# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DECIPHER", "Biostrings")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DECIPHER)
library(Biostrings)

# 1. Create seqs_path (FASTA file of training sequences)
seqs <- DNAStringSet(c(
  "Root;Bacteria;Firmicutes;Bacilli;Bacillales;Bacillaceae;Bacillus" = "ATGCGTACGTTAGC",
  "Root;Bacteria;Proteobacteria;Gammaproteobacteria;Enterobacteriales;Enterobacteriaceae;Escherichia" = "ATGCGCACGTTAGC"
))
writeXStringSet(seqs, "seqs_path")

# 2. Create rank_path (taxid text file containing taxonomic ranks)
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

# 3. Create fas (FASTA file of query sequences to classify)
fas_in <- system.file("extdata", "Bacteria_175seqs.fas", package="DECIPHER")
if (file.exists(fas_in)) {
  file.copy(fas_in, "fas")
} else {
  writeXStringSet(seqs, "fas")
}