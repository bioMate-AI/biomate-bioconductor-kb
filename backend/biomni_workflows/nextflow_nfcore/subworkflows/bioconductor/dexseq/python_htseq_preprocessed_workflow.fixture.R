library(DEXSeq)
library(pasilla)

target_files <- c(
  "treated1fb.txt", "treated2fb.txt", "treated3fb.txt", 
  "untreated1fb.txt", "untreated2fb.txt", "untreated3fb.txt", "untreated4fb.txt", 
  "Dmel.BDGP5.25.62.DEXSeq.chr.gff"
)

# Discover the actual files shipped in the pasilla package
pasilla_files <- list.files(system.file("extdata", package="pasilla"), recursive=TRUE, full.names=TRUE)

for (f in target_files) {
  src <- pasilla_files[basename(pasilla_files) == f]
  if (length(src) > 0) {
    file.copy(src[1], f, overwrite=TRUE)
  } else {
    # Fallback dummy creation if the file is missing from the installation
    if (grepl("\\.txt$", f)) {
      writeLines(c("FBgn0000256:E001\t10", "FBgn0000256:E002\t20"), f)
    } else if (grepl("\\.gff$", f)) {
      writeLines(c('chr2L\tDEXSeq\texonic_part\t3872658\t3872947\t.\t-\t.\ttranscripts "FBtr0077511"; exonic_part_number "001"; gene_id "FBgn0000256"'), f)
    }
  }
}