library(SpliceWiz)
library(NxtIRFdata)

file.copy(chrZ_genome(), "genome.fa", overwrite = TRUE)
file.copy(chrZ_gtf(), "transcripts.gtf", overwrite = TRUE)

fq1 <- c(
  "@SEQ_ID_1",
  "GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT",
  "+",
  "!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65"
)
writeLines(fq1, "sample_1.fastq")

fq2 <- c(
  "@SEQ_ID_1",
  "GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT",
  "+",
  "!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65"
)
writeLines(fq2, "sample_2.fastq")