library(limma)
library(ExiMiR)

# 1. Create Targets.txt
targets_df <- data.frame(
  SlideNumber = c(1, 2),
  Cy3 = c("sample1_Cy3.txt", "sample2_Cy3.txt"),
  Cy5 = c("sample1_Cy5.txt", "sample2_Cy5.txt"),
  stringsAsFactors = FALSE
)
write.table(targets_df, file = "Targets.txt", sep = "\t", row.names = FALSE, quote = FALSE)

# 2. Create GAL file (array annotation)
gal_lines <- c(
  "ATF\t1.0",
  "1\t1",
  '"Type=GenePix ArrayList V1.0"',
  "Block\tRow\tColumn\tID\tName",
  "1\t1\t1\tID1\tGene1",
  "1\t1\t2\tID2\tGene2",
  "1\t2\t1\tID3\tGene3",
  "1\t2\t2\tID4\tGene4"
)
writeLines(gal_lines, "array.gal")

# 3. Create ImaGene raw data files
imagene_df <- data.frame(
  Field = 1,
  `Meta Row` = 1,
  `Meta Column` = 1,
  Row = c(1, 1, 2, 2),
  Column = c(1, 2, 1, 2),
  `Gene ID` = c("ID1", "ID2", "ID3", "ID4"),
  `Signal Mean` = c(1000, 2000, 3000, 4000),
  `Background Mean` = c(100, 150, 200, 250),
  check.names = FALSE
)

write.table(imagene_df, file = "sample1_Cy3.txt", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(imagene_df, file = "sample1_Cy5.txt", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(imagene_df, file = "sample2_Cy3.txt", sep = "\t", row.names = FALSE, quote = FALSE)
write.table(imagene_df, file = "sample2_Cy5.txt", sep = "\t", row.names = FALSE, quote = FALSE)