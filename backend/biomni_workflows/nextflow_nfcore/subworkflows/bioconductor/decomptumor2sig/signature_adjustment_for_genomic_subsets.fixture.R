library(decompTumor2Sig)
library(TxDb.Hsapiens.UCSC.hg19.knownGene)

# 1. COSMIC mutational signatures
# Recreating the Alexandrov-type signatures format (version 2) as shown in the vignette
cosmic_content <- c(
  "Substitution Type\tTrinucleotide\tSomatic Mutation Type\tSignature 1",
  "C>A\tACA\tA[C>A]A\t0.011098326166",
  "C>A\tACC\tA[C>A]C\t0.009149340734",
  "C>A\tACG\tA[C>A]G\t0.001490070468",
  "C>A\tACT\tA[C>A]T\t0.006233885236",
  "T>G\tTTG\tT[T>G]G\t0.002031076880",
  "T>G\tTTT\tT[T>G]T\t0.004030128160"
)
writeLines(cosmic_content, "COSMIC mutational signatures")

# 2. TxDb.Hsapiens.UCSC.hg19.knownGene
# The workflow requires the transcript database. We serialize the loaded TxDb object 
# to match the declared input file name.
saveRDS(TxDb.Hsapiens.UCSC.hg19.knownGene, "TxDb.Hsapiens.UCSC.hg19.knownGene")