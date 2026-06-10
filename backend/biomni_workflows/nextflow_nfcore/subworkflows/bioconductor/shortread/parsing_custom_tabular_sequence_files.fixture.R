library(ShortRead)

# Construct a synthetic s_2_export.txt file matching the Solexa export format
# The workflow expects at least 21 columns, where column 9 is the DNA sequence 
# and column 10 is the quality score.
lines <- c(
  paste(c("HWI-EAS88", "3", "2", "1", "451", "945", "", "", 
          "CCAGAGCCCCCCGCTCACTCCTGAACCAGTCTCTC", "YQMIMIMMLMMIGIGMFICMFFFIMMHIIHAAGAH", 
          "NM", "", "", "", "", "", "", "", "", "", "N"), collapse="\t"),
  paste(c("HWI-EAS88", "3", "2", "1", "451", "946", "", "", 
          "AGCCTCCCTCTTTCTGAATATACGGCAGAGCTGTT", "ZXZUYXZQYYXUZXYZYYZZXXZZIMFHXQSUPPO", 
          "NM", "", "", "", "", "", "", "", "", "", "N"), collapse="\t"),
  paste(c("HWI-EAS88", "3", "2", "1", "451", "947", "", "", 
          "ACCAAAAACACCACATACACGAGCAACACACGTAC", "LGDHLILLLLLLLIGFLLALDIFDILLHFIAECAE", 
          "NM", "", "", "", "", "", "", "", "", "", "N"), collapse="\t")
)

writeLines(lines, "s_2_export.txt")